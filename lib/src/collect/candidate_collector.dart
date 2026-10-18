import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/exposed_types.dart';
import 'package:ciach/src/collect/kept_declarations.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/public_api.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Range;

final _log = Logger('ciach.finder');

const _uncollectedFile = 'Could not list declarations; file skipped.';

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
  late final _kept = KeptDeclarations(options.entryPoints, _sources);

  /// The pairing names in each conditional-import variant that was read,
  /// candidates or not; see [ConditionalImports.share].
  final declaredInVariants = <String, Set<String>>{};

  /// One line per declaration kept as an entry point or by a marker, for
  /// `--verbose`.
  void reportSkipped() => _kept.report();

  /// The declarations of the open file [path] worth checking, where
  /// [exposedTypes] reads the same [client].
  Future<List<Candidate>> collect(
    LspClient client,
    ExposedTypes exposedTypes,
    String path,
    String rootPath,
  ) async {
    final uri = File(path).uri;
    final pendingSymbols = client.documentSymbol(uri);
    final pendingOutline = client.outline(uri);
    final pendingTokens = semanticTokensOrEmpty(client, _sources, path);
    final List<DocumentSymbol> symbols;
    final Outline outline;
    try {
      symbols = await pendingSymbols;
      outline = await pendingOutline;
    } on Object catch (e) {
      // The other results are no longer needed.
      pendingOutline.ignore();
      pendingTokens.ignore();
      if (e is! LspRequestException) {
        rethrow;
      }
      recordProblem(_uncollectedFile, e, path: path);
      return const [];
    }
    _sources.cacheSemanticTokens(path, await pendingTokens);
    if (_conditionalImports.contains(path)) {
      declaredInVariants[path] = ConditionalImports.pairingNames(symbols);
    }
    final exposed = await exposedTypes.of(path, outline);
    final relativePath = relativePosix(path, rootPath);
    final markers = _Markers(IgnoreMarkers.parse(_sources.content(path)));
    // The whole walk has to run before the filter: it records the entry-point
    // containers the filter drops, and a container comes before its members.
    final candidates = _collect(
      uri,
      path,
      relativePath,
      symbols,
      null,
      null,
      null,
      false,
      _OutlineIndex(outline),
      markers,
      exposed,
    ).toList();
    markers.warnAbout(relativePath);
    return _kept.withoutContainers(candidates, relativePath).toList();
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container.
  ///
  /// [parentIsEnum] marks children of an enum declaration so their enum values
  /// are remapped to the `enum-value` kind.
  Iterable<Candidate> _collect(
    Uri uri,
    String path,
    String relativePath,
    List<DocumentSymbol> symbols,
    String? container,
    Candidate? containerCandidate,
    ExportedMembers? containerExports,
    bool parentIsEnum,
    _OutlineIndex outlines,
    _Markers markers,
    Map<String, ExposedMembers> exposedTypes,
  ) sync* {
    final statement = _Statement();
    for (final (symbol, outline) in _declarations(
      relativePath,
      symbols,
      outlines,
    )) {
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
        isInExposedType: switch (exposedTypes[container]) {
          .all => true,
          .instance => symbol.kind != .constructor && !_isStatic(path, symbol),
          null => false,
        },
      );
      final exports = exportsOf(symbol, leadingMetadata) ?? containerExports;
      if (_isCandidate(
        relativePath,
        candidate,
        leadingMetadata,
        containerExports: containerExports,
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
        symbol.children ?? const [],
        childContainer,
        childContainerCandidate,
        exports,
        symbol.kind == .enum$,
        outlines,
        markers,
        exposedTypes,
      );
    }
  }

  /// Whether [symbol] in [path] is a static member. A value of a type or of
  /// its subtype reaches no constructors or static members, so those of a
  /// private type stay private unless a type alias names the type.
  bool _isStatic(String path, DocumentSymbol symbol) =>
      _sources
          .semanticTokens(path)
          ?.startingAt(symbol.selectionRange.start)
          ?.modifiers
          .contains('static') ??
      false;

  /// Pairs each of [symbols] with its outline entry, and skips a symbol the
  /// outline doesn't list.
  ///
  /// A `test(...)` or `group(...)` call is not a declaration, and removing it
  /// would delete the test, so it is replaced by the declarations inside its
  /// closure.
  Iterable<(DocumentSymbol, Outline)> _declarations(
    String relativePath,
    List<DocumentSymbol> symbols,
    _OutlineIndex outlines,
  ) sync* {
    for (final symbol in symbols) {
      final outline = outlines[symbol];
      if (outline == null) {
        _log.fine(
          'Skipped $relativePath:${symbol.selectionRange.start.line + 1} '
          "${symbol.name}: the analysis server's outline has no entry for it.",
        );
      } else if (outline.element.isDeclaration) {
        yield (symbol, outline);
      } else {
        yield* _declarations(
          relativePath,
          symbol.children ?? const [],
          outlines,
        );
      }
    }
  }

  /// Whether [candidate] is public and left out: by `--no-public`, or as part
  /// of an API that `exported-packages` leaves out. A private declaration is
  /// never left out, and a member of a private type or an unnamed extension
  /// is private too.
  bool _skipsPublic(Candidate candidate) {
    if (candidate.isPrivate) {
      return false;
    }
    final symbol = candidate.symbol;
    return !options.includePublic ||
        (_publicApi?.exposes(
              candidate.path,
              candidate.container ?? symbol.name,
            ) ??
            false);
  }

  /// Returns whether [candidate], whose doc comment and annotations start on
  /// line [start], is checked: neither kept by one of [markers] nor left out.
  bool _isCandidate(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata, {
    required ExportedMembers? containerExports,
    required _Markers markers,
    required int start,
  }) {
    if (markers.keeping(
          start: start,
          nameLine: candidate.symbol.selectionRange.start.line,
        )
        case final kept?) {
      _kept.byMarker(relativePath, candidate, kept);
      return false;
    }
    return _shouldConsider(
      relativePath,
      candidate,
      leadingMetadata,
      containerExports: containerExports,
    );
  }

  /// Returns whether the references to [candidate] should be checked.
  bool _shouldConsider(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata, {
    required ExportedMembers? containerExports,
  }) {
    final symbol = candidate.symbol;
    if (!options.kinds.contains(
      symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
        isMixin: candidate.isMixin,
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
    if (_kept.isEntryPoint(
      relativePath,
      candidate,
      leadingMetadata,
      containerExports,
    )) {
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
    if (options.skipOperators && symbol.isOperator) {
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
    // Symbols reachable from native code / reflection are not really unused.
    if (leadingMetadata.any(
      (t) => t.type == 'string' && t.text.contains('vm:entry-point'),
    )) {
      return false;
    }
    return true;
  }
}

/// The field statement that the symbols being collected belong to, for the
/// declarators after the first.
///
/// A field statement's doc comment, annotations and modifiers sit on its first
/// declarator, so a later one (`b` in `@override final int a, b;`) reads that
/// statement's instead of its own, which are empty. Likewise, a marker above
/// the statement keeps every declarator.
final class _Statement {
  var _metadata = const <SemanticToken>[];
  var _start = 0;

  /// The leading metadata of the declaration [outline], whose own is
  /// [ownMetadata], and the line its statement starts on.
  ({Iterable<SemanticToken> leadingMetadata, int start}) next(
    Outline outline,
    Iterable<SemanticToken> ownMetadata,
  ) {
    final isField = outline.element.kind == .field;
    if (isField && outline.range.start == outline.codeRange.start) {
      return (leadingMetadata: _metadata, start: _start);
    }
    _metadata = isField ? ownMetadata.toList() : const [];
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

/// Outline nodes by document symbol: a symbol's `range` is its node's
/// `codeRange`.
final class _OutlineIndex {
  _OutlineIndex(Outline root)
    : _byCodeRange = {
        for (final node in root.descendants) _key(node.codeRange): node,
      };

  final Map<_RangeKey, Outline> _byCodeRange;

  Outline? operator [](DocumentSymbol symbol) =>
      _byCodeRange[_key(symbol.range)];

  static _RangeKey _key(Range range) => (
    range.start.line,
    range.start.character,
    range.end.line,
    range.end.character,
  );
}

typedef _RangeKey = (int, int, int, int);
