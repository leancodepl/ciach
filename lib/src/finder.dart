/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:async';
import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Position, SymbolKind;

/// A declaration to check: the symbol plus enough context to query references
/// for it and to report it later.
typedef _Candidate = ({
  Uri uri,
  String path,
  DocumentSymbol symbol,
  String? container,
  bool isEnumValue,
});

/// How a candidate's references classify it.
enum _RefStatus {
  /// At least one real (non-doc-comment) reference.
  used,

  /// No real references, but at least one dartdoc `[Xxx]` comment link.
  docOnly,

  /// No references of any kind.
  unused,
}

/// A minimal lexical token: a source span plus whether it is an identifier /
/// keyword (`isWord`) or a single punctuation character. Whitespace, comments,
/// and string literals are dropped during tokenization, so `case`/`default`
/// keywords and brackets can be matched without tripping over a `case` that
/// only appears inside a comment or string.
typedef _Token = ({int start, int end, bool isWord, String value});

/// Finds declarations that are never referenced by driving the Dart analysis
/// server over LSP.
///
/// For every declaration reported by `textDocument/documentSymbol`, a
/// `textDocument/references` query is issued at the declaration's name, with
/// `includeDeclaration: false`. An empty result means the declaration is unused.
class Ciach {
  /// Creates a finder that runs with the given [options].
  Ciach(this.options);

  /// The configuration for this run.
  final FinderOptions options;

  /// Symbol kinds that introduce a lexical scope; their name becomes the
  /// container for nested members.
  static const _typeLikeKinds = <SymbolKind>{
    .class$,
    .interface$,
    .enum$,
    .struct,
  };

  /// Names of Dart's overloadable operators. The analysis server reports an
  /// `operator +`/`operator ==`/… declaration as a plain [SymbolKind.method]
  /// named exactly one of these — there is no distinct operator symbol kind —
  /// so this is the only reliable way to recognize one.
  static const _operatorNames = <String>{
    '+',
    '-',
    '*',
    '/',
    '%',
    '~/',
    '&',
    '|',
    '^',
    '~',
    '<<',
    '>>',
    '>>>',
    '<',
    '<=',
    '>',
    '>=',
    '==',
    '[]',
    '[]=',
  };

  bool _isOperator(DocumentSymbol symbol) =>
      symbol.kind == .method && _operatorNames.contains(symbol.name);

  /// Lines of every scanned file, keyed by absolute path, populated as each
  /// file is opened in [_collectCandidatesFor]. Reused to classify reference
  /// locations as doc comments without re-reading files from disk.
  final _fileLines = <String, List<String>>{};

  /// Whether [location] points at a dartdoc `[Xxx]`-style reference rather
  /// than real code — i.e. its line, in the file it points into, starts with
  /// `///`. Block (`/** */`) doc comments aren't recognized; `///` is the
  /// standard and lint-enforced style.
  bool _isDocReference(Location location) {
    final lines = _linesFor(_pathOf(location.uri));
    final line = location.range.start.line;
    if (line < 0 || line >= lines.length) {
      return false;
    }
    return lines[line].trim().startsWith('///');
  }

  /// The absolute file path a reference [uri] points at.
  String _pathOf(String uri) => Uri.parse(uri).toFilePath();

  /// The lines of the file at [path], read (and cached) on demand.
  List<String> _linesFor(String path) =>
      _fileLines[path] ??= _readFile(path)?.split('\n') ?? const [];

  void _report(String message) => options.onProgress?.call(message);

  /// Runs the analysis and returns the declarations that are never referenced.
  Future<FinderResult> run() async {
    final stopwatch = Stopwatch()..start();
    final rootPath = p.normalize(p.absolute(options.rootPath));

    final discovered = discoverDartFilesSplit(options);
    final files = discovered.candidates;
    _report('Discovered ${files.length} Dart file(s) to scan.');

    if (files.isEmpty) {
      return .new(
        unused: const [],
        docOnly: const [],
        filesScanned: 0,
        declarationsChecked: 0,
        elapsed: stopwatch.elapsed,
      );
    }

    _report('Starting Dart analysis server…');
    final client = await LspClient.start(
      dartExecutable: options.dartExecutable,
    );

    final unused = <UnusedDeclaration>[];
    final docOnly = <UnusedDeclaration>[];
    var declarationsChecked = 0;

    try {
      await client.initialize(Directory(rootPath).uri);
      _report('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

      // Phase 0: open the excluded generated files (without collecting them as
      // candidates) so a reference query for a declaration used *only* from
      // generated code — e.g. a `toJson` called from a `.g.dart` — resolves.
      if (discovered.warmOnly.isNotEmpty) {
        _report('Warming ${discovered.warmOnly.length} generated file(s)…');
        await _mapPooled<String, bool>(
          discovered.warmOnly,
          options.concurrency,
          (path) => _warmFile(client, path),
        );
      }

      // Phase 1: open every file and collect its candidate declarations,
      // concurrently. Opening keeps each file's resolved unit warm in the
      // server's cache; without it, reference queries against files the server
      // has evicted come back empty and produce false "unused" reports.
      _report('Collecting declarations from ${files.length} file(s)…');
      final perFile = await _mapPooled<String, List<_Candidate>>(
        files,
        options.concurrency,
        (path) => _collectCandidatesFor(client, path),
      );
      final candidates = [for (final list in perFile) ...list];
      declarationsChecked = candidates.length;

      // Phase 2: check references for every candidate through a single global
      // pool, so the server stays saturated instead of stalling between files.
      // Progress is reported per file: each file's remaining count is tracked
      // and a line is emitted as soon as its last declaration is checked. Files
      // with no candidates are already counted as done.
      _report('Checking references for $declarationsChecked declaration(s)…');
      final remainingPerFile = <String, int>{};
      for (final candidate in candidates) {
        remainingPerFile.update(
          candidate.path,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final totalFiles = files.length;
      var filesDone = totalFiles - remainingPerFile.length;

      final refsByCandidate = await _mapPooled<_Candidate, List<Location>>(
        candidates,
        options.concurrency,
        (candidate) async {
          final refs = await client.references(
            candidate.uri,
            candidate.symbol.selectionRange.start,
          );
          final remaining = remainingPerFile[candidate.path]! - 1;
          remainingPerFile[candidate.path] = remaining;
          if (remaining == 0) {
            filesDone++;
            _report(
              '[$filesDone/$totalFiles] '
              '${p.relative(candidate.path, from: rootPath)}',
            );
          }
          return refs;
        },
      );

      final statuses = [
        for (var i = 0; i < candidates.length; i++)
          _classify(candidates[i], refsByCandidate[i]),
      ];

      // Names of classes flagged unused, per file. A whole dead class is
      // removed as one node, taking its own constructor(s) with it, so those
      // constructors must not also be reported (or removed) on their own.
      final deadClassNames = <String, Set<String>>{};
      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        if (statuses[i] == _RefStatus.unused &&
            candidate.symbol.kind == .class$) {
          deadClassNames
              .putIfAbsent(candidate.path, () => <String>{})
              .add(candidate.symbol.name);
        }
      }

      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        switch (statuses[i]) {
          case _RefStatus.unused:
            if (_isConstructorOfDeadClass(candidate, deadClassNames)) {
              break;
            }
            final isClass = candidate.symbol.kind == .class$;
            final paired = isClass
                ? _pairedStateRemovals(
                    candidate,
                    refsByCandidate[i],
                    candidates,
                    refsByCandidate,
                    rootPath,
                  )
                : const <CoupledRemoval>[];
            // Under --unused-union-members, a class kept dead only by type
            // patterns (never constructed, only matched) is still *reported*,
            // but --remove must not touch it or its pattern arms: deleting a
            // member of a sealed union and its scattered `case`s is a source
            // rewrite this tool won't attempt. Such findings are report-only —
            // removal is blocked, so the remover leaves them and anything
            // coupled to them entirely alone.
            final patternMatched =
                isClass &&
                options.unusedUnionMembers &&
                _isPatternMatchedClass(candidate, refsByCandidate[i]);
            unused.add(
              _toUnused(
                candidate,
                rootPath,
                coupledRemovals: paired,
                removalBlocked: patternMatched,
              ),
            );
          case _RefStatus.docOnly:
            docOnly.add(_toUnused(candidate, rootPath));
          case _RefStatus.used:
            break;
        }
      }
    } finally {
      await client.dispose();
    }

    unused.sort(_byLocation);
    docOnly.sort(_byLocation);
    stopwatch.stop();
    return .new(
      unused: unused,
      docOnly: docOnly,
      filesScanned: files.length,
      declarationsChecked: declarationsChecked,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Opens [path] in the analysis server without collecting candidates from
  /// it, so references *into* still-scanned code from this file resolve.
  /// Returns whether the file could be read and opened.
  Future<bool> _warmFile(LspClient client, String path) async {
    final content = _readFile(path);
    if (content == null) {
      return false;
    }
    final uri = File(path).uri;
    client.didOpen(uri, content);
    _fileLines[path] = content.split('\n');
    return true;
  }

  /// Fetches the symbols for [path] and returns the declarations worth checking.
  Future<List<_Candidate>> _collectCandidatesFor(
    LspClient client,
    String path,
  ) async {
    final content = _readFile(path);
    if (content == null) {
      return const [];
    }
    final uri = File(path).uri;
    client.didOpen(uri, content);
    final symbols = await client.documentSymbol(uri);
    final lines = content.split('\n');
    _fileLines[path] = lines;
    final out = <_Candidate>[];
    _collectCandidates(uri, path, symbols, null, false, lines, out);
    return out;
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container.
  ///
  /// [parentIsEnum] marks children of an enum declaration: the analysis
  /// server reports enum values with the same [SymbolKind.enum$] kind as the
  /// enum type itself, so this is the only way to tell them apart.
  void _collectCandidates(
    Uri uri,
    String path,
    List<DocumentSymbol> symbols,
    String? container,
    bool parentIsEnum,
    List<String> lines,
    List<_Candidate> out,
  ) {
    for (final symbol in symbols) {
      if (_shouldConsider(symbol, lines)) {
        out.add((
          uri: uri,
          path: path,
          symbol: symbol,
          container: container,
          isEnumValue: parentIsEnum && symbol.kind == .enum$,
        ));
      }
      final childContainer = _typeLikeKinds.contains(symbol.kind)
          ? symbol.name
          : container;
      _collectCandidates(
        uri,
        path,
        symbol.children ?? const [],
        childContainer,
        symbol.kind == .enum$,
        lines,
        out,
      );
    }
  }

  bool _shouldConsider(DocumentSymbol symbol, List<String> lines) {
    if (!options.kinds.contains(symbol.kind)) {
      return false;
    }
    // The program entry point is never "unused".
    if (symbol.kind == .function && symbol.name == 'main') {
      return false;
    }
    final private = _isPrivateName(symbol.name);
    if (!private && !options.includePublic) {
      return false;
    }
    if (options.skipOperators && _isOperator(symbol)) {
      return false;
    }

    final leading = _leadingMetadata(symbol, lines);
    if (options.skipOverrides && leading.contains('@override')) {
      return false;
    }
    // Symbols reachable from native code / reflection are not really unused.
    if (leading.contains('vm:entry-point')) {
      return false;
    }
    return true;
  }

  UnusedDeclaration _toUnused(
    _Candidate candidate,
    String rootPath, {
    List<CoupledRemoval> coupledRemovals = const [],
    bool removalBlocked = false,
  }) {
    final symbol = candidate.symbol;
    final start = symbol.selectionRange.start;
    final name = _declarationName(symbol, candidate.container);
    return .new(
      name: name,
      kind: symbol.kind,
      filePath: _relPath(candidate.path, rootPath),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      isPrivate: _isPrivateName(name),
      container: candidate.container,
      isEnumValue: candidate.isEnumValue,
      range: _rangeOf(symbol),
      coupledRemovals: coupledRemovals,
      removalBlocked: removalBlocked,
    );
  }

  /// Classifies a candidate from the references reported for it.
  ///
  /// Non-class candidates keep the simple rule: any real (non-doc) reference
  /// means used, only doc-comment links means doc-only, none means unused.
  ///
  /// Classes get [_classifyClass], which discounts *self-references* — the
  /// class's own body, and the `State<Self>` StatefulWidget pairing — so a
  /// class kept alive only by its own unnamed constructor's declaration (whose
  /// name coincides with the class) is correctly seen as dead.
  _RefStatus _classify(_Candidate candidate, List<Location> refs) {
    if (candidate.symbol.kind == .class$) {
      return _classifyClass(candidate, refs);
    }
    if (refs.isEmpty) {
      return _RefStatus.unused;
    }
    final hasRealRef = refs.any((loc) => !_isDocReference(loc));
    return hasRealRef ? _RefStatus.used : _RefStatus.docOnly;
  }

  /// Classifies a class by its references, ignoring self-references.
  ///
  /// A class is used only if some reference is a real (non-doc) reference from
  /// *outside* the class itself; if the only outside references are doc-comment
  /// links it is doc-only, and otherwise (only self-references, or none at all)
  /// it is unused. This is deliberately conservative: any single unexplained
  /// outside reference keeps the class alive, so the failure mode is missing a
  /// dead class, never deleting a live one.
  _RefStatus _classifyClass(_Candidate candidate, List<Location> refs) {
    var hasExternalCode = false;
    var hasExternalDoc = false;
    var hasPatternMatch = false;
    for (final loc in refs) {
      if (_isSelfClassReference(candidate, loc)) {
        continue;
      }
      if (_isDocReference(loc)) {
        hasExternalDoc = true;
        continue;
      }
      // With --unused-union-members, a reference that is confidently a *type
      // pattern* (a `case`/if-case/while-case pattern, or a switch-expression
      // arm) is a *match*, not a construction: if the type is never
      // constructed, no such match can ever fire, so it is discounted like a
      // self-reference. Any reference that is not confidently a type pattern
      // falls through to `hasExternalCode` and keeps the class alive — the
      // conservative choice (nested sub-patterns and pattern-variable
      // declarations are intentionally not recognized, so they keep it alive).
      if (options.unusedUnionMembers && _isPatternRef(loc)) {
        hasPatternMatch = true;
        continue;
      }
      hasExternalCode = true;
    }
    if (hasExternalCode) {
      return _RefStatus.used;
    }
    // Matched-only-by-a-pattern (never constructed) is dead code, not a softer
    // doc-only report.
    if (hasPatternMatch) {
      return _RefStatus.unused;
    }
    return hasExternalDoc ? _RefStatus.docOnly : _RefStatus.unused;
  }

  /// Whether [loc] is a reference to [candidate] that does not count as a use.
  ///
  /// Two shapes qualify:
  ///
  /// 1. A reference inside the class's own source span — its body, signature,
  ///    or leading doc/annotation lines. This covers the unnamed constructor's
  ///    declaration (`Foo` in `Foo();`, reported by the server as a reference
  ///    to the class), a `State<Foo>` return type on the widget's own
  ///    `createState`, and any purely-internal self-use.
  /// 2. A `State<Foo>` type-argument reference anywhere — the StatefulWidget
  ///    pairing. `State<Foo>` can only ever denote the state object of the
  ///    `Foo` widget, so it never means `Foo` itself is used elsewhere.
  bool _isSelfClassReference(_Candidate candidate, Location loc) {
    if (_pathOf(loc.uri) == candidate.path) {
      final lines = _linesFor(candidate.path);
      final top = _metadataTopLine(candidate.symbol, lines);
      final pos = loc.range.start;
      final afterTop = pos.line >= top;
      if (afterTop && _atOrBeforeEnd(pos, candidate.symbol.range.end)) {
        return true;
      }
    }
    return _isStatePairingReference(candidate.symbol.name, loc);
  }

  /// Whether [loc] is the class name [className] appearing as the sole type
  /// argument of `State<…>`, e.g. `class _FooState extends State<Foo>`.
  bool _isStatePairingReference(String className, Location loc) {
    final start = loc.range.start;
    final end = loc.range.end;
    if (start.line != end.line) {
      return false;
    }
    final lines = _linesFor(_pathOf(loc.uri));
    if (start.line < 0 || start.line >= lines.length) {
      return false;
    }
    final line = lines[start.line];
    if (start.character < 0 ||
        end.character > line.length ||
        start.character > end.character) {
      return false;
    }
    if (line.substring(start.character, end.character) != className) {
      return false;
    }
    return _statePrefix.hasMatch(line.substring(0, start.character)) &&
        _stateSuffix.hasMatch(line.substring(end.character));
  }

  /// The `State<` immediately preceding a type argument, with a token boundary
  /// before `State` so `MyState<…>`/`FooState<…>` don't match.
  static final _statePrefix = RegExp(r'(?:^|[^A-Za-z0-9_$])State<\s*$');

  /// The `>` that closes a single `State<…>` type argument.
  static final _stateSuffix = RegExp(r'^\s*>');

  bool _isConstructorOfDeadClass(
    _Candidate candidate,
    Map<String, Set<String>> deadClassNames,
  ) =>
      candidate.symbol.kind == .constructor &&
      candidate.container != null &&
      (deadClassNames[candidate.path]?.contains(candidate.container) ?? false);

  /// The extra spans to remove alongside a dead [widget] class: the paired
  /// private `State<Widget>` subclass, when there is exactly one and it is used
  /// only from within the widget (via `createState`). Returns an empty list for
  /// a plain class, or a StatefulWidget whose State is referenced elsewhere.
  ///
  /// Removing the widget on its own would leave
  /// `class _S extends State<Widget>` referring to a now-deleted type — a build
  /// break — so the State is coupled to the widget's removal, but it is not
  /// itself reported.
  List<CoupledRemoval> _pairedStateRemovals(
    _Candidate widget,
    List<Location> widgetRefs,
    List<_Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final out = <CoupledRemoval>[];
    for (final loc in widgetRefs) {
      if (!_isStatePairingReference(widget.symbol.name, loc)) {
        continue;
      }
      if (_pathOf(loc.uri) != widget.path) {
        continue;
      }
      // The widget's own `createState` return type is inside the widget and
      // removed with it; only a pairing reference outside the widget points at
      // the separate State subclass.
      if (_withinSymbol(loc.range.start, widget.symbol)) {
        continue;
      }
      for (var j = 0; j < candidates.length; j++) {
        final state = candidates[j];
        if (state.symbol.kind != .class$ ||
            state.path != widget.path ||
            identical(state, widget) ||
            !_withinSymbol(loc.range.start, state.symbol)) {
          continue;
        }
        if (_referencedOnlyWithin(
          refsByCandidate[j],
          widget.symbol,
          widget.path,
        )) {
          out.add((
            filePath: _relPath(state.path, rootPath),
            range: _rangeOf(state.symbol),
          ));
        }
        break;
      }
    }
    return out;
  }

  /// Whether every *code* reference in [refs] lies within [enclosing] in
  /// [path] — used to confirm a paired State subclass is reachable only from
  /// its widget. Doc-comment links (e.g. a `[_FooState]` mention) are ignored:
  /// documentation never keeps code alive, so it must not block coupling.
  bool _referencedOnlyWithin(
    List<Location> refs,
    DocumentSymbol enclosing,
    String path,
  ) {
    for (final loc in refs) {
      if (_isDocReference(loc)) {
        continue;
      }
      if (_pathOf(loc.uri) != path ||
          !_withinSymbol(loc.range.start, enclosing)) {
        return false;
      }
    }
    return true;
  }

  /// Whether [pos] falls within [symbol]'s full source range.
  bool _withinSymbol(Position pos, DocumentSymbol symbol) {
    final start = symbol.range.start;
    final afterStart =
        pos.line > start.line ||
        (pos.line == start.line && pos.character >= start.character);
    return afterStart && _atOrBeforeEnd(pos, symbol.range.end);
  }

  bool _atOrBeforeEnd(Position pos, Position end) =>
      pos.line < end.line ||
      (pos.line == end.line && pos.character <= end.character);

  DeclarationRange _rangeOf(DocumentSymbol symbol) => (
    startLine: symbol.range.start.line,
    startColumn: symbol.range.start.character,
    endLine: symbol.range.end.line,
    endColumn: symbol.range.end.character,
  );

  /// [absPath] expressed relative to [rootPath], with `/` separators, matching
  /// [UnusedDeclaration.filePath].
  String _relPath(String absPath, String rootPath) =>
      p.split(p.relative(absPath, from: rootPath)).join('/');

  /// Whether [candidate] — already classified as unused under
  /// `--unused-union-members` — is kept dead by *type patterns*: at least one
  /// of its non-self, non-doc references is a `case`/switch-expression pattern
  /// match rather than a construction.
  ///
  /// Such a class is reported (a human should know the type is never
  /// constructed, only matched) but its removal is *blocked*: deleting a member
  /// of a sealed union and its scattered pattern arms is a source rewrite this
  /// tool won't attempt, so `--remove` leaves it — and its arms — in place.
  bool _isPatternMatchedClass(_Candidate candidate, List<Location> refs) {
    for (final loc in refs) {
      if (_isSelfClassReference(candidate, loc) || _isDocReference(loc)) {
        continue;
      }
      if (_isPatternRef(loc)) {
        return true;
      }
    }
    return false;
  }

  /// Whether reference [loc] to a class is a *type pattern* — a match, not a
  /// construction — for the opt-in dead-union-member detection.
  ///
  /// Recognized as patterns:
  ///
  /// * A `case <Type>` pattern — in a `switch` statement, or in an
  ///   `if (x case …)` / `while (x case …)` header.
  /// * A switch-*expression* arm `<Type>… => …,`.
  ///
  /// Everything else (construction, type annotations, `extends`/`implements`,
  /// static access, nested sub-patterns, pattern-variable declarations) is not
  /// a pattern — a real use that keeps the class alive.
  bool _isPatternRef(Location loc) {
    final located = _locateTypeToken(loc);
    if (located == null) {
      return false;
    }
    final (:tokens, :ti) = located;

    final prev = ti > 0 ? tokens[ti - 1] : null;
    if (prev != null && prev.isWord && prev.value == 'case') {
      // Any `case <Type>` — switch statement, if-case, or while-case — matches
      // the type without constructing it.
      return true;
    }

    return _isSwitchExprArm(tokens, ti);
  }

  /// Resolves [loc] to the lexer token index of the referenced type name,
  /// returning it with the file's cached tokens, or `null` if the reference
  /// doesn't line up with a word token.
  ({List<_Token> tokens, int ti})? _locateTypeToken(Location loc) {
    final path = _pathOf(loc.uri);
    final content = _contentFor(path);
    if (content.isEmpty) {
      return null;
    }
    final lineStarts = _lineStartsFor(path);
    final startOff = _offsetOfPosition(lineStarts, content, loc.range.start);
    if (startOff == null) {
      return null;
    }
    final tokens = _tokensFor(path);
    final ti = _tokenIndexAt(tokens, startOff);
    if (ti == null || !tokens[ti].isWord) {
      return null;
    }
    return (tokens: tokens, ti: ti);
  }

  /// Whether the type token at [ti] begins a switch-*expression* arm: preceded
  /// by the `{`/`,` of a `switch (…) {` body and followed by a top-level `=>`.
  bool _isSwitchExprArm(List<_Token> tokens, int ti) {
    if (ti == 0) {
      return false;
    }
    final prev = tokens[ti - 1];
    if (prev.isWord || (prev.value != '{' && prev.value != ',')) {
      return false;
    }
    // Find the enclosing `{` (walking back over a preceding arm if prev is `,`).
    final braceIndex = _enclosingOpener(tokens, ti - 1);
    if (braceIndex == null || tokens[braceIndex].value != '{') {
      return false;
    }
    // `{` must close a `switch (…)` header: the token before it is `)` whose
    // matching `(` is immediately preceded by `switch`.
    final closeParen = braceIndex - 1;
    if (closeParen < 0 ||
        tokens[closeParen].isWord ||
        tokens[closeParen].value != ')') {
      return false;
    }
    final openParen = _matchingOpenParen(tokens, closeParen);
    if (openParen == null || openParen == 0) {
      return false;
    }
    final kw = tokens[openParen - 1];
    if (!kw.isWord || kw.value != 'switch') {
      return false;
    }
    // A top-level `=>` must follow the pattern (so this is an arm, not e.g. a
    // set/map entry inside a collection literal).
    var depth = 0;
    for (var k = ti + 1; k < tokens.length; k++) {
      final t = tokens[k];
      if (t.isWord) {
        continue;
      }
      switch (t.value) {
        case '(' || '[' || '{':
          depth++;
        case ')' || ']' || '}':
          if (depth == 0) {
            return false;
          }
          depth--;
        case ',' || ';':
          if (depth == 0) {
            return false;
          }
        case '=':
          if (depth == 0 &&
              k + 1 < tokens.length &&
              !tokens[k + 1].isWord &&
              tokens[k + 1].value == '>') {
            return true;
          }
      }
    }
    return false;
  }

  /// Walking backward from [from], the index of the nearest enclosing (not yet
  /// closed) opening bracket, or `null` if the scan runs off the start.
  int? _enclosingOpener(List<_Token> tokens, int from) {
    var depth = 0;
    for (var k = from; k >= 0; k--) {
      final t = tokens[k];
      if (t.isWord) {
        continue;
      }
      switch (t.value) {
        case ')' || ']' || '}':
          depth++;
        case '(' || '[' || '{':
          if (depth == 0) {
            return k;
          }
          depth--;
      }
    }
    return null;
  }

  /// The index of the `(` matching the `)` at [closeIndex], or `null`.
  int? _matchingOpenParen(List<_Token> tokens, int closeIndex) {
    var depth = 0;
    for (var k = closeIndex; k >= 0; k--) {
      final t = tokens[k];
      if (t.isWord) {
        continue;
      }
      switch (t.value) {
        case ')' || ']' || '}':
          depth++;
        case '(' || '[' || '{':
          depth--;
          if (depth == 0) {
            return t.value == '(' ? k : null;
          }
      }
    }
    return null;
  }

  /// Absolute offset of an LSP [position] in [content], or `null` if out of
  /// range. LSP columns are UTF-16 code units, which is exactly how Dart
  /// indexes a `String`, so the arithmetic needs no conversion.
  int? _offsetOfPosition(
    List<int> lineStarts,
    String content,
    Position position,
  ) {
    if (position.line < 0 || position.line >= lineStarts.length) {
      return null;
    }
    final offset = lineStarts[position.line] + position.character;
    if (offset < 0 || offset > content.length) {
      return null;
    }
    return offset;
  }

  /// The index of the token whose span starts exactly at [offset], or `null`
  /// if none does. Tokens are ordered by start, so this is a binary search.
  int? _tokenIndexAt(List<_Token> tokens, int offset) {
    var lo = 0;
    var hi = tokens.length - 1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      final start = tokens[mid].start;
      if (start == offset) {
        return mid;
      }
      if (start < offset) {
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return null;
  }

  final _contentCache = <String, String>{};
  final _lineStartsCache = <String, List<int>>{};
  final _tokensCache = <String, List<_Token>>{};

  /// The full text of [path], reconstructed from the cached lines so it matches
  /// the document content the analysis server resolved positions against.
  String _contentFor(String path) =>
      _contentCache[path] ??= _linesFor(path).join('\n');

  List<int> _lineStartsFor(String path) =>
      _lineStartsCache[path] ??= _computeLineStarts(_contentFor(path));

  List<_Token> _tokensFor(String path) =>
      _tokensCache[path] ??= _tokenize(_contentFor(path));

  static List<int> _computeLineStarts(String content) {
    final starts = <int>[0];
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '\n') {
        starts.add(i + 1);
      }
    }
    return starts;
  }

  static bool _isIdentStart(String ch) =>
      (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
      (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
      ch == '_' ||
      ch == r'$';

  static bool _isIdentPart(String ch) =>
      _isIdentStart(ch) || (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0);

  /// Splits [content] into [_Token]s, skipping whitespace, `//` and (nesting)
  /// `/* */` comments, and every string-literal form (single/double,
  /// triple-quoted, raw, and `${…}`/`$id` interpolation). Everything else is
  /// emitted as either a word token or a single-character punctuation token.
  static List<_Token> _tokenize(String content) {
    final tokens = <_Token>[];
    final n = content.length;
    var i = 0;
    while (i < n) {
      final ch = content[i];
      if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r') {
        i++;
        continue;
      }
      if (ch == '/' && i + 1 < n && content[i + 1] == '/') {
        i += 2;
        while (i < n && content[i] != '\n') {
          i++;
        }
        continue;
      }
      if (ch == '/' && i + 1 < n && content[i + 1] == '*') {
        i = _skipBlockComment(content, i);
        continue;
      }
      if ((ch == 'r' || ch == 'R') &&
          i + 1 < n &&
          (content[i + 1] == "'" || content[i + 1] == '"')) {
        i = _skipString(content, i + 1, raw: true);
        continue;
      }
      if (ch == "'" || ch == '"') {
        i = _skipString(content, i, raw: false);
        continue;
      }
      if (_isIdentStart(ch)) {
        final start = i;
        i++;
        while (i < n && _isIdentPart(content[i])) {
          i++;
        }
        tokens.add((
          start: start,
          end: i,
          isWord: true,
          value: content.substring(start, i),
        ));
        continue;
      }
      tokens.add((start: i, end: i + 1, isWord: false, value: ch));
      i++;
    }
    return tokens;
  }

  /// Skips a (possibly nested) `/* … */` block comment starting at [from],
  /// returning the index just past it.
  static int _skipBlockComment(String content, int from) {
    final n = content.length;
    var i = from + 2;
    var depth = 1;
    while (i < n && depth > 0) {
      if (content[i] == '/' && i + 1 < n && content[i + 1] == '*') {
        depth++;
        i += 2;
      } else if (content[i] == '*' && i + 1 < n && content[i + 1] == '/') {
        depth--;
        i += 2;
      } else {
        i++;
      }
    }
    return i;
  }

  /// Skips a string literal whose opening quote is at [from], returning the
  /// index just past the closing quote. Handles triple quotes, escapes, and —
  /// unless [raw] — `${…}`/`$id` interpolation (whose braces and nested
  /// strings are matched so a `}` or quote inside them doesn't end the string).
  static int _skipString(String content, int from, {required bool raw}) {
    final n = content.length;
    final quote = content[from];
    final triple =
        from + 2 < n &&
        content[from + 1] == quote &&
        content[from + 2] == quote;
    var i = from + (triple ? 3 : 1);
    while (i < n) {
      final c = content[i];
      if (!raw && c == r'\') {
        i += 2;
        continue;
      }
      if (!raw && c == r'$') {
        i = _skipInterpolation(content, i);
        continue;
      }
      if (c == quote) {
        if (!triple) {
          return i + 1;
        }
        if (i + 2 < n && content[i + 1] == quote && content[i + 2] == quote) {
          return i + 3;
        }
      }
      if (!triple && c == '\n') {
        // Unterminated single-line string; stop at the newline rather than run on.
        return i;
      }
      i++;
    }
    return n;
  }

  /// Skips a `$`-interpolation starting at [from] (the `$`), returning the
  /// index just past it. Handles both `$identifier` and brace-matched `${…}`.
  static int _skipInterpolation(String content, int from) {
    final n = content.length;
    if (from + 1 < n && content[from + 1] == '{') {
      var i = from + 2;
      var depth = 1;
      while (i < n && depth > 0) {
        final c = content[i];
        if (c == '{') {
          depth++;
          i++;
        } else if (c == '}') {
          depth--;
          i++;
        } else if (c == "'" || c == '"') {
          i = _skipString(content, i, raw: false);
        } else {
          i++;
        }
      }
      return i;
    }
    var i = from + 1;
    while (i < n && _isIdentPart(content[i])) {
      i++;
    }
    return i;
  }

  /// The first line of [symbol] including its contiguous leading
  /// doc-comment/annotation block (mirrors the removal-side extension), so a
  /// self-referencing dartdoc link in the class's own doc counts as a
  /// self-reference.
  int _metadataTopLine(DocumentSymbol symbol, List<String> lines) {
    final nameLine = symbol.selectionRange.start.line;
    var top = symbol.range.start.line <= nameLine
        ? symbol.range.start.line
        : nameLine;
    while (top - 1 >= 0) {
      final trimmed = lines[top - 1].trim();
      final isMetaLine =
          trimmed.isEmpty ||
          trimmed.startsWith('@') ||
          trimmed.startsWith('//') ||
          trimmed.startsWith('/*') ||
          trimmed.startsWith('*') ||
          trimmed.endsWith('*/');
      if (isMetaLine) {
        top--;
      } else {
        break;
      }
    }
    return top;
  }

  /// The name to report for [symbol].
  ///
  /// The analysis server names constructor symbols with the class included
  /// (`Foo` for the unnamed constructor, `Foo.named` for a named one). The
  /// container already carries the class, so strip that prefix here and report
  /// the unnamed constructor as `new` — yielding `Foo.named` / `Foo.new` once
  /// combined with the container, rather than `Foo.Foo.named` / `Foo.Foo`.
  String _declarationName(DocumentSymbol symbol, String? container) {
    if (symbol.kind != .constructor) {
      return symbol.name;
    }
    final raw = symbol.name;
    if (container != null && raw.startsWith('$container.')) {
      return raw.substring(container.length + 1);
    }
    return raw.isEmpty || raw == container ? 'new' : raw;
  }

  bool _isPrivateName(String name) {
    final simple = name.contains('.') ? name.split('.').last : name;
    return simple.startsWith('_');
  }

  /// Returns the annotations, modifiers and doc comments immediately preceding
  /// [symbol], as a single string, for cheap annotation detection.
  String _leadingMetadata(DocumentSymbol symbol, List<String> lines) {
    final nameLine = symbol.selectionRange.start.line;
    final top = _metadataTopLine(symbol, lines);
    final end = nameLine < lines.length ? nameLine : lines.length - 1;
    return lines.sublist(top, end + 1).join('\n');
  }

  static int _byLocation(UnusedDeclaration a, UnusedDeclaration b) {
    final byFile = a.filePath.compareTo(b.filePath);
    if (byFile != 0) {
      return byFile;
    }
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  }

  String? _readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }

  /// Runs [fn] over [items] with at most [concurrency] futures in flight,
  /// preserving input order in the returned list.
  Future<List<R>> _mapPooled<T, R>(
    List<T> items,
    int concurrency,
    Future<R> Function(T) fn,
  ) async {
    final results = List<R?>.filled(items.length, null);
    var next = 0;

    Future<void> worker() async {
      while (true) {
        final index = next++;
        if (index >= items.length) {
          return;
        }
        results[index] = await fn(items[index]);
      }
    }

    final workerCount = concurrency < items.length ? concurrency : items.length;
    await Future.wait([for (var i = 0; i < workerCount; i++) worker()]);
    return results.cast<R>();
  }
}
