import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/js_interop.dart';
import 'package:ciach/src/conventions/test_reflective_loader.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/problems.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
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

  /// The declarations of the open file [path] worth checking.
  Future<List<Candidate>> collect(
    LspClient client,
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
    final relativePath = relativePosix(path, rootPath);
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
    ).toList();
    return _withoutEntryPointContainers(candidates, relativePath).toList();
  }

  /// One line per skipped entry point, except the ubiquitous `main`.
  void reportSkipped() {
    if (!_log.isLoggable(.FINE)) {
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
      _log.fine(
        'Skipped ${skipped.path}:${skipped.line} ${skipped.name}: '
        '${skipped.reason}.',
      );
    }
  }

  /// [candidates] less the types a member entry point lives in; see
  /// [_entryPointContainers]. Their other members stay candidates.
  Iterable<Candidate> _withoutEntryPointContainers(
    List<Candidate> candidates,
    String relativePath,
  ) sync* {
    for (final candidate in candidates) {
      final symbol = candidate.symbol;
      final rule =
          candidate.container == null && typeLikeKinds.contains(symbol.kind)
          ? _entryPointContainers[DeclKey(relativePath, symbol.name)]
          : null;
      if (rule == null) {
        yield candidate;
        continue;
      }
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: symbol.name,
        reason: 'declares the entry point ${rule.label}',
      ));
    }
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
    _ExportedMembers? containerExports,
    bool parentIsEnum,
    _OutlineIndex outlines,
  ) sync* {
    // A field statement's doc comment, annotations and modifiers sit on its
    // first declarator, so a later one (`b` in `@override final int a, b;`)
    // reads that statement's instead of its own, which are empty.
    var statementMetadata = const <SemanticToken>[];
    for (final symbol in symbols) {
      final outline = outlines[symbol];
      if (outline == null) {
        _log.fine(
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
      final isTypeLike = typeLikeKinds.contains(symbol.kind);
      final exports = isTypeLike
          ? _exportedMembers(leadingMetadata)
          : containerExports;
      if (_shouldConsider(
        relativePath,
        candidate,
        leadingMetadata,
        containerExports: containerExports,
        ownExports: isTypeLike ? exports : null,
      )) {
        yield candidate;
      }
      yield* _collect(
        uri,
        path,
        relativePath,
        symbol.children ?? const [],
        isTypeLike ? symbol.name : container,
        isTypeLike ? candidate : containerCandidate,
        exports,
        symbol.kind == .enum$,
        outlines,
      );
    }
  }

  _ExportedMembers? _exportedMembers(Iterable<SemanticToken> leadingMetadata) {
    if (isJsExported(leadingMetadata)) {
      return .jsExport;
    }
    if (isReflectiveTest(leadingMetadata)) {
      return .reflectiveTest;
    }
    return null;
  }

  /// The `extends` clause's class name of the class [path]'s [symbol].
  String? _superclassOf(String path, DocumentSymbol symbol) {
    if (symbol.kind != .class$) {
      return null;
    }
    final start = _sources.offsetOf(path, symbol.selectionRange.end);
    final end = _sources.offsetOf(path, symbol.range.end);
    if (start == null || end == null) {
      return null;
    }
    final rest = _sources.content(path).substring(start, end);
    final brace = rest.indexOf('{');
    return _extendsClause
        .firstMatch(brace < 0 ? rest : rest.substring(0, brace))
        ?.group(1);
  }

  /// No nested type parameters.
  static final _extendsClause = RegExp(
    r'^\s*(?:<[^<>]*>)?\s*extends\s+([A-Za-z_$][\w$]*)',
  );

  String? _calledFromOutside(
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    _ExportedMembers? containerExports,
    _ExportedMembers? ownExports,
  ) {
    final symbol = candidate.symbol;
    if (ownExports == .jsExport || isJsExported(leadingMetadata)) {
      return 'exported to JavaScript by `@JSExport`';
    }
    if (isPrivateName(symbol.name) || symbol.kind == .constructor) {
      return null;
    }
    return switch (containerExports) {
      .jsExport => 'exported to JavaScript by `@JSExport` on its class',
      .reflectiveTest
          when symbol.kind == .method && isReflectiveTestMethod(symbol.name) =>
        'run by `defineReflectiveTests`',
      _ => null,
    };
  }

  /// Whether [candidate] should have its references checked.
  bool _shouldConsider(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata, {
    required _ExportedMembers? containerExports,
    required _ExportedMembers? ownExports,
  }) {
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
    if (_entryPoints.match(
          relativePath,
          symbol,
          container,
          containerSuperclass: () => switch (candidate.containerSymbol) {
            final containerSymbol? => _superclassOf(
              candidate.path,
              containerSymbol,
            ),
            null => null,
          },
        )
        case final rule?) {
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: container == null ? symbol.name : '$container.${symbol.name}',
        reason: rule.reason,
      ));
      if (container != null) {
        _entryPointContainers[DeclKey(relativePath, container)] ??= rule;
      }
      return false;
    }
    if (_calledFromOutside(
          candidate,
          leadingMetadata,
          containerExports,
          ownExports,
        )
        case final reason?) {
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: container == null
            ? symbol.declarationName(container)
            : '$container.${symbol.declarationName(container)}',
        reason: reason,
      ));
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

/// Members of a type called from outside Dart source.
enum _ExportedMembers { jsExport, reflectiveTest }

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
