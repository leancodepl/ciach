import 'dart:io';

import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/kept_declarations.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/problems.dart';
import 'package:ciach/src/source/document_symbol.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/public_api.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

const _uncollectedFile = 'Could not list declarations; file skipped.';

const _compileErrors =
    'Has compile errors; the declarations that it uses may be reported.';

/// Which declarations get their references checked: every document symbol
/// of a scanned file, less the kinds, visibilities, entry points and
/// conventions the options leave out.
final class CandidateCollector {
  CandidateCollector({
    required this.options,
    required SourceIndex sources,
    required FreezedUnions freezed,
    PublicApi? publicApi,
    ConditionalImports? conditionalImports,
  }) : _sources = sources,
       _freezed = freezed,
       _publicApi = publicApi,
       _conditionalImports = conditionalImports ?? .empty;

  final FinderOptions options;
  final SourceIndex _sources;

  /// Freezed-union tracking, fed as candidates are collected.
  final FreezedUnions _freezed;

  /// What other packages can import, when exported declarations are left out.
  final PublicApi? _publicApi;

  final ConditionalImports _conditionalImports;

  /// What this run leaves unchecked on purpose, and why.
  late final _entryPoints = EntryPoints(options.entryPoints);

  late final _kept = KeptDeclarations(_entryPoints);

  /// The pairing names in each conditional-import variant that was read,
  /// candidates or not; see [ConditionalImports.share].
  final declaredInVariants = <String, Set<String>>{};

  /// One line per declaration kept as an entry point or by a marker, for
  /// `--verbose`.
  void reportSkipped() => _kept.report();

  /// The declarations of the open file [path] worth checking. [files]
  /// resolves the file.
  Future<List<Candidate>> collect(
    ResolvedFiles files,
    String path,
    String rootPath,
  ) async {
    final file = await files.of(path);
    if (file == null) {
      recordProblem(_uncollectedFile, unresolvedFile, path: path);
      return const [];
    }
    if (file.firstError case (:final position, :final message)) {
      recordProblem(_compileErrors, message, path: path, position: position);
    }
    final relativePath = relativePosix(path, rootPath);
    if (_conditionalImports.contains(path)) {
      declaredInVariants[path] = ConditionalImports.pairingNames(file.symbols);
    }
    final markers = _Markers(.parse(_sources.content(path)));
    // The whole walk has to run before the filter: it records the entry-point
    // containers the filter drops, and a container comes before its members.
    final candidates = _collect(
      File(path).uri,
      path,
      relativePath,
      file,
      file.symbols,
      file.outline.children,
      null,
      null,
      const [],
      false,
      markers,
    ).toList();
    markers.warnAbout(relativePath);
    return _kept.withoutContainers(candidates, relativePath).toList();
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container. [outlines] are
  /// the outline nodes that [symbols] were built from, in the same order.
  ///
  /// [parentIsEnum] marks children of an enum declaration so their enum values
  /// are remapped to the `enum-value` kind.
  Iterable<Candidate> _collect(
    Uri uri,
    String path,
    String relativePath,
    ResolvedFile file,
    List<DocumentSymbol> symbols,
    List<Outline> outlines,
    String? container,
    Candidate? containerCandidate,
    List<KeptMembers> containerMembers,
    bool parentIsEnum,
    _Markers markers,
  ) sync* {
    final statement = _Statement();
    for (final (symbol, outline) in _declarations(symbols, outlines)) {
      final (:leadingMetadata, :start) = statement.next(
        outline,
        _sources.leadingMetadata(path, outline),
      );
      _freezed.noteIfAnnotated(path, symbol, leadingMetadata);
      final candidate = Candidate(
        uri: uri,
        path: path,
        symbol: symbol,
        outline: outline,
        container: container,
        containerSymbol: containerCandidate?.symbol,
        containerOutline: containerCandidate?.outline,
        isEnumValue: parentIsEnum && symbol.kind == .enum$,
        isPreventInstantiationCtor: symbol.isPreventInstantiationMarker(
          symbols,
        ),
      );
      final declaration = _kept.declarationOf(
        relativePath,
        candidate,
        leadingMetadata,
        file,
      );
      if (_isCandidate(
        candidate,
        declaration,
        containerMembers: containerMembers,
        markers: markers,
        start: start,
      )) {
        yield candidate;
      }
      final (
        childContainer,
        childContainerCandidate,
      ) = typeLikeKinds.contains(symbol.kind)
          ? (symbol.name, candidate)
          : (container, containerCandidate);
      yield* _collect(
        uri,
        path,
        relativePath,
        file,
        symbol.children,
        outline.children,
        childContainer,
        childContainerCandidate,
        _kept.keptMembersOf(declaration) ?? containerMembers,
        symbol.kind == .enum$,
        markers,
      );
    }
  }

  /// Pairs each of [symbols] with the node of [outlines] that it was built
  /// from.
  ///
  /// A `test(...)` or `group(...)` call is not a declaration, and removing it
  /// would delete the test, so it is replaced by the declarations inside its
  /// closure.
  static Iterable<(DocumentSymbol, Outline)> _declarations(
    List<DocumentSymbol> symbols,
    List<Outline> outlines,
  ) sync* {
    for (final (i, symbol) in symbols.indexed) {
      final outline = outlines[i];
      if (outline.element.isDeclaration) {
        yield (symbol, outline);
      } else {
        yield* _declarations(symbol.children, outline.children);
      }
    }
  }

  /// Whether [candidate] is public and left out: by `--no-public`, or as part
  /// of an API that `exported-packages` leaves out. An unnamed extension and
  /// its members are private, since no other library can use them.
  bool _skipsPublic(Candidate candidate) {
    final symbol = candidate.symbol;
    if (isPrivateName(symbol.name) || candidate.belongsToUnnamedExtension) {
      return false;
    }
    return !options.includePublic ||
        (_publicApi?.exposes(
              candidate.path,
              candidate.container ?? symbol.name,
            ) ??
            false);
  }

  /// Returns whether [candidate], which the rules read as [declaration] and
  /// whose doc comment and annotations start on line [start], is checked:
  /// neither kept by one of [markers] nor left out.
  bool _isCandidate(
    Candidate candidate,
    ResolvedDeclaration declaration, {
    required List<KeptMembers> containerMembers,
    required _Markers markers,
    required int start,
  }) {
    if (markers.keeping(
          start: start,
          nameLine: candidate.symbol.selectionRange.start.line,
        )
        case final kept?) {
      _kept.byMarker(declaration.relativePath, candidate, kept);
      return false;
    }
    return _shouldConsider(
      candidate,
      declaration,
      containerMembers: containerMembers,
    );
  }

  /// Returns whether the references to [candidate] should be checked.
  bool _shouldConsider(
    Candidate candidate,
    ResolvedDeclaration declaration, {
    required List<KeptMembers> containerMembers,
  }) {
    final symbol = candidate.symbol;
    final leadingMetadata = declaration.leadingMetadata;
    if (!options.kinds.contains(
      symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
        isMixin: candidate.isMixin,
        isTypeAlias: candidate.isTypeAlias,
      ),
    )) {
      return false;
    }
    // Only the messages of a gen-l10n file are checked: removing one from the
    // ARB file leaves the code around them.
    if (translationsOf(candidate, options.translations, options.rootPath) !=
            null &&
        !isTranslationMessage(candidate)) {
      return false;
    }
    if (_kept.isEntryPoint(declaration, containerMembers)) {
      return false;
    }
    if (symbol.kind == .namespace &&
        !candidate.isExtension &&
        !candidate.isExtensionType) {
      return false;
    }
    if (_skipsPublic(candidate)) {
      return false;
    }
    // Already represented by the header's constructor symbol.
    if (symbol.isPrimaryConstructorBody) {
      return false;
    }

    if (options.skipOverrides &&
        leadingMetadata.any((t) => t.isAnnotationNamed('override'))) {
      return false;
    }
    return true;
  }
}

/// The variable statement that the symbols being collected belong to, for the
/// declarators after the first. It declares fields or top-level variables.
///
/// A variable statement's doc comment, annotations and modifiers sit on its
/// first declarator, so a later one (`b` in `@override final int a, b;`) reads
/// that statement's instead of its own, which are empty. Likewise, a marker
/// above the statement keeps every declarator.
final class _Statement {
  var _metadata = const <SemanticToken>[];
  var _start = 0;

  /// The leading metadata of the declaration [outline], whose own is
  /// [ownMetadata], and the line its statement starts on.
  ({Iterable<SemanticToken> leadingMetadata, int start}) next(
    Outline outline,
    Iterable<SemanticToken> ownMetadata,
  ) {
    final isVariable = const <OutlineKind>{
      .field,
      .topLevelVariable,
    }.contains(outline.element.kind);
    if (isVariable && outline.range.start == outline.codeRange.start) {
      return (leadingMetadata: _metadata, start: _start);
    }
    _metadata = isVariable ? ownMetadata.toList() : const [];
    _start = outline.range.start.line;
    return (leadingMetadata: ownMetadata, start: _start);
  }
}

/// The markers of one file, and which of them kept a declaration.
final class _Markers {
  _Markers(this._markers);

  final IgnoreMarkers _markers;
  final _used = <MarkerAt>{};

  /// The marker keeping the declaration that starts on [start] and is named
  /// on [nameLine]; see [IgnoreMarkers.keeping].
  MarkerAt? keeping({required int start, required int nameLine}) {
    if (_markers.isEmpty) {
      return null;
    }
    final keepers = _markers.keepers(start: start, nameLine: nameLine);
    _used.addAll(keepers);
    return keepers.firstOrNull;
  }

  /// Warns about the malformed markers in the file at [relativePath], and
  /// those that kept nothing.
  void warnAbout(String relativePath) {
    final warnings = [
      ..._markers.issues,
      for (final marker in _markers.all)
        if (!_used.contains(marker))
          (
            line: marker.line,
            message: switch (marker.marker) {
              ignoreMarker =>
                '`// $ignoreMarker` keeps no declaration: on a line of its own it applies to the declaration on the next line, after code to the one named on its line',
              _ => 'the `// ${marker.marker}` range keeps no declaration',
            },
          ),
    ]..sort((a, b) => a.line.compareTo(b.line));
    for (final (:line, :message) in warnings) {
      _log.warning('$relativePath:${line + 1}: $message.');
    }
  }
}
