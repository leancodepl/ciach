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
import 'package:ciach/src/public_api.dart';
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
    PublicApi? publicApi,
  }) : _sources = sources,
       _freezed = freezed,
       _publicApi = publicApi;

  final FinderOptions options;
  final SourceIndex _sources;

  /// Freezed-union tracking, fed as candidates are collected.
  final FreezedUnions _freezed;

  /// What other packages can import, when exported declarations are left out.
  final PublicApi? _publicApi;

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
        reason: switch (rule.superclass) {
          final superclass? =>
            'extends `$superclass`, so its public methods are entry points',
          null => 'declares the entry point ${rule.name}',
        },
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
      final exports = _exportsOf(symbol, leadingMetadata) ?? containerExports;
      if (_shouldConsider(
        relativePath,
        candidate,
        leadingMetadata,
        containerExports: containerExports,
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
      );
    }
  }

  /// Whether [candidate] is public and left out: by `--no-public`, or as part
  /// of the package's API by `--no-exported`.
  bool _skipsPublic(Candidate candidate) {
    final symbol = candidate.symbol;
    if (isPrivateName(symbol.name)) {
      return false;
    }
    return !options.includePublic ||
        (_publicApi?.exposes(
              candidate.path,
              candidate.container ?? symbol.name,
            ) ??
            false);
  }

  /// Returns which members of the type [symbol] are called from outside the
  /// Dart source. The annotation on the type decides this. Returns `null`
  /// when [symbol] is not a type, or when the type has no such annotation.
  _ExportedMembers? _exportsOf(
    DocumentSymbol symbol,
    Iterable<SemanticToken> leadingMetadata,
  ) {
    if (!typeLikeKinds.contains(symbol.kind)) {
      return null;
    }
    if (isJsExported(leadingMetadata)) {
      return .jsExport;
    }
    if (isReflectiveTest(leadingMetadata)) {
      return .reflectiveTest;
    }
    return null;
  }

  /// Returns the name of the class that [symbol] extends. [symbol] is a class
  /// that is declared in the file at [path]. Returns `null` when [symbol] is
  /// not a class, or when the class has no `extends` clause.
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

  /// Matches the `extends` clause that follows a class name. The type
  /// parameters before the clause must not be nested, so a class with
  /// `<T extends List<int>>` is not matched.
  static final _extendsClause = RegExp(
    r'^\s*(?:<[^<>]*>)?\s*extends\s+([A-Za-z_$][\w$]*)',
  );

  String? _calledFromOutside(
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    _ExportedMembers? containerExports,
  ) {
    final symbol = candidate.symbol;
    if (isJsExported(leadingMetadata)) {
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

  /// Returns whether [candidate] is called by a framework or a tool. Such a
  /// declaration has no reference in the source code. Every entry point that
  /// is found here is recorded, so that `--verbose` can list it.
  bool _isEntryPoint(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    _ExportedMembers? containerExports,
  ) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    final rule = _entryPoints.match(
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
    );
    if (rule != null && container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??= rule;
    }
    final reason =
        rule?.reason ??
        _calledFromOutside(candidate, leadingMetadata, containerExports);
    if (reason == null) {
      return false;
    }
    final name = symbol.declarationName(container);
    _skippedEntryPoints.add((
      path: relativePath,
      line: symbol.selectionRange.start.line + 1,
      name: container == null ? name : '$container.$name',
      reason: reason,
    ));
    return true;
  }

  /// Returns whether the references to [candidate] should be checked.
  bool _shouldConsider(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata, {
    required _ExportedMembers? containerExports,
  }) {
    final symbol = candidate.symbol;
    if (!options.kinds.contains(
      symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
      ),
    )) {
      return false;
    }
    if (_isEntryPoint(
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

/// The members of a type that are called from outside the Dart source.
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
