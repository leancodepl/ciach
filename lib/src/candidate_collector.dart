import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Range;

/// Which declarations get their references checked: every document symbol
/// of a scanned file, less the kinds, visibilities, entry points and
/// conventions the options leave out.
final class CandidateCollector {
  CandidateCollector({
    required this.options,
    required SourceIndex sources,
    required FreezedUnions freezed,
  }) : _sources = sources,
       _freezed = freezed;

  final FinderOptions options;
  final SourceIndex _sources;

  /// Freezed-union tracking, fed as candidates are collected.
  final FreezedUnions _freezed;

  late final _entryPoints = EntryPoints(options.entryPoints);

  /// Skipped as entry points this run, for `--verbose`.
  final _skippedEntryPoints = <_SkippedEntryPoint>[];

  /// Types whose member is an entry point, by `(relative path, type name)`:
  /// the generated call that reaches `MyPlugin.registerWith` names `MyPlugin`
  /// too, so the type is not a candidate either.
  final _entryPointContainers = <DeclKey, EntryPoint>{};

  void _report(String message) => options.onProgress?.call(message);

  /// The declarations of the open file [path] worth checking.
  Future<List<Candidate>> collect(
    LspClient client,
    String path,
    String rootPath,
  ) async {
    final uri = File(path).uri;
    final (symbols, outline, tokens) = await (
      client.documentSymbol(uri),
      client.outline(uri),
      semanticTokensOrEmpty(client, _sources, path),
    ).wait;
    _sources.cacheSemanticTokens(path, tokens);
    final relativePath = relativePosix(path, rootPath);
    final out = <Candidate>[];
    _collect(
      uri,
      path,
      relativePath,
      symbols,
      null,
      null,
      false,
      _OutlineIndex(outline),
      out,
    );
    return _withoutEntryPointContainers(out, relativePath);
  }

  /// One line per skipped entry point, except the ubiquitous `main`.
  void reportSkipped() {
    if (options.onProgress == null) {
      return;
    }
    _skippedEntryPoints.sort((a, b) {
      final byFile = a.path.compareTo(b.path);
      return byFile != 0 ? byFile : a.line.compareTo(b.line);
    });
    for (final skipped in _skippedEntryPoints) {
      if (skipped.name == 'main') {
        continue;
      }
      _report(
        'Skipped ${skipped.path}:${skipped.line} ${skipped.name}: '
        '${skipped.reason}.',
      );
    }
  }

  /// [candidates] less the types a member entry point lives in; see
  /// [_entryPointContainers]. Their other members stay candidates.
  List<Candidate> _withoutEntryPointContainers(
    List<Candidate> candidates,
    String relativePath,
  ) {
    if (_entryPointContainers.isEmpty) {
      return candidates;
    }
    final kept = <Candidate>[];
    for (final candidate in candidates) {
      final symbol = candidate.symbol;
      final rule =
          candidate.container == null && typeLikeKinds.contains(symbol.kind)
          ? _entryPointContainers[DeclKey(relativePath, symbol.name)]
          : null;
      if (rule == null) {
        kept.add(candidate);
        continue;
      }
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: symbol.name,
        reason: 'declares the entry point ${rule.name}',
      ));
    }
    return kept;
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container.
  ///
  /// [parentIsEnum] marks children of an enum declaration so their enum values
  /// are remapped to the `enum-value` kind.
  void _collect(
    Uri uri,
    String path,
    String relativePath,
    List<DocumentSymbol> symbols,
    String? container,
    Candidate? containerCandidate,
    bool parentIsEnum,
    _OutlineIndex outlines,
    List<Candidate> out,
  ) {
    // A field statement's doc comment, annotations and modifiers sit on its
    // first declarator, so a later one (`b` in `@override final int a, b;`)
    // reads that statement's instead of its own, which are empty.
    var statementMetadata = const <SemanticToken>[];
    for (final symbol in symbols) {
      final outline = outlines[symbol];
      if (outline == null) {
        _report(
          'Skipped $relativePath:${symbol.selectionRange.start.line + 1} '
          "${symbol.name}: the analysis server's outline has no entry for it.",
        );
        continue;
      }
      final ownMetadata = _sources.leadingMetadata(path, outline);
      final isField = outline.element.kind == .field;
      final continuesStatement =
          isField && outline.range.start == outline.codeRange.start;
      final leadingMetadata = continuesStatement
          ? statementMetadata
          : ownMetadata;
      statementMetadata = isField && !continuesStatement
          ? ownMetadata.toList()
          : const [];
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
      if (_shouldConsider(relativePath, candidate, leadingMetadata)) {
        out.add(candidate);
      }
      final isTypeLike = typeLikeKinds.contains(symbol.kind);
      _collect(
        uri,
        path,
        relativePath,
        symbol.children ?? const [],
        isTypeLike ? symbol.name : container,
        isTypeLike ? candidate : containerCandidate,
        symbol.kind == .enum$,
        outlines,
        out,
      );
    }
  }

  /// Whether [candidate] should have its references checked.
  bool _shouldConsider(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
  ) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    if (!options.kinds.contains(
      symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
      ),
    )) {
      return false;
    }
    // Called by a framework or tool, with no source reference to find.
    if (_entryPoints.match(relativePath, symbol, container) case final rule?) {
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: rule.name,
        reason: rule.reason,
      ));
      if (container != null) {
        _entryPointContainers.putIfAbsent(
          DeclKey(relativePath, container),
          () => rule,
        );
      }
      return false;
    }
    if (symbol.kind == .namespace &&
        !candidate.isExtension &&
        !candidate.isExtensionType) {
      return false;
    }
    if (!isPrivateName(symbol.name) && !options.includePublic) {
      return false;
    }
    if (options.skipOperators && symbol.isOperator) {
      return false;
    }
    // Always skipped (no flag): implicit-call syntax is unresolvable, like
    // operators.
    if (symbol.isCallMethod) {
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

/// A skipped entry point: root-relative POSIX path, one-based line, the name
/// as the rule spells it, and why.
typedef _SkippedEntryPoint = ({
  String path,
  int line,
  String name,
  String reason,
});

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
