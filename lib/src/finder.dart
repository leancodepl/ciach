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
/// and string literals are dropped during tokenization, so `values`/`.` can be
/// matched without tripping over a `values` that only appears inside a comment
/// or string.
typedef _Token = ({int start, int end, bool isWord, String value});

/// A file path paired with a declaration name, used as a map key to look up
/// per-declaration facts (here: enums whose `.values` is iterated).
typedef _DeclKey = ({String path, String name});

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

  /// Whether [symbol] is a `call` method, which makes its object callable via
  /// implicit-call syntax `obj(...)`. The analysis server's reference search
  /// does not resolve that syntax back to the `call` declaration — exactly as
  /// it fails to resolve infix operator syntax (see [_isOperator]) — so a used
  /// `call` method is reported as unused every time.
  bool _isCallMethod(DocumentSymbol symbol) =>
      symbol.kind == .method && symbol.name == 'call';

  /// Whether [symbol] is a private constructor (`Foo._`, `Foo._named`). The
  /// analysis server names a constructor with its class included (`Foo` for
  /// the unnamed constructor, `Foo.named` for a named one), so the private
  /// marker is a name segment after the last `.` that starts with `_`. The
  /// unnamed constructor (no `.`) is never treated as private here, even for a
  /// private class.
  bool _isPrivateConstructor(DocumentSymbol symbol) {
    if (symbol.kind != .constructor) {
      return false;
    }
    final name = symbol.name;
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot + 1 < name.length && name[dot + 1] == '_';
  }

  /// Whether [symbol] is the classic *prevent-instantiation marker*: a private
  /// constructor that is the **sole** constructor of its class **and** takes
  /// **no parameters** (`Foo._();`). Such a constructor is intentionally never
  /// referenced, and removing it would re-add the implicit default constructor
  /// and make the class publicly instantiable — so it is skipped rather than
  /// reported.
  ///
  /// [siblings] are the class members the constructor lives among (its parent's
  /// `children` in the document-symbol tree), used to count how many
  /// constructors the class declares. A private constructor that is *named
  /// alongside other constructors* (the class declares more than one) or that
  /// *takes parameters* is not this marker: it can be genuinely dead, so it is
  /// reported normally.
  bool _isPreventInstantiationMarker(
    DocumentSymbol symbol,
    List<DocumentSymbol> siblings,
  ) {
    if (!_isPrivateConstructor(symbol)) {
      return false;
    }
    // Sole constructor: exactly one constructor among the class's members.
    final constructorCount = siblings
        .where((s) => s.kind == .constructor)
        .length;
    if (constructorCount != 1) {
      return false;
    }
    return _hasNoParameters(symbol);
  }

  /// Whether [symbol]'s parameter list is empty.
  ///
  /// The analysis server reports a constructor's (or function's) signature in
  /// [DocumentSymbol.detail] as the parenthesized parameter list — `()` when
  /// there are no parameters, `(int a)` / `(int a, {String b})` when there are.
  /// If the server omits the detail we cannot tell the arity, so we
  /// conservatively treat it as empty (skip) to avoid regressing on the classic
  /// zero-parameter marker.
  bool _hasNoParameters(DocumentSymbol symbol) {
    final detail = symbol.detail?.trim();
    if (detail == null || detail.isEmpty) {
      return true;
    }
    final inner = detail.startsWith('(') && detail.endsWith(')')
        ? detail.substring(1, detail.length - 1).trim()
        : detail;
    return inner.isEmpty;
  }

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

      // Phase 0: warm the generated files that are excluded from the scan.
      // Opening them keeps their resolved units in the server's cache, so a
      // reference query for a declaration used *only* from generated code
      // (e.g. a `toJson` called from a `.g.dart` part) resolves instead of
      // coming back empty. Their own declarations are never collected as
      // candidates.
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

      final statuses = [for (final refs in refsByCandidate) _classify(refs)];

      // ---- Enum `.values` detection fix ----
      //
      // An enum value reached only through `.values` iteration is not dead: the
      // iteration reaches every value without naming any individually. Two
      // forms count — the qualified `EnumType.values` (found among the enum
      // type's references, via [_isDotValuesRef]) and the implicit bare `values`
      // getter inside the enum's own body (invisible to a references query, so
      // detected by a source scan in [_enumIteratesOwnValues]). Collect the
      // enums whose `.values` is iterated so none of their values is flagged.
      final enumValuesIterated = <_DeclKey>{};
      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        final symbol = candidate.symbol;
        if (symbol.kind == .enum$ && !candidate.isEnumValue) {
          if (refsByCandidate[i].any(_isDotValuesRef) ||
              _enumIteratesOwnValues(candidate)) {
            enumValuesIterated.add(_key(candidate.path, symbol.name));
          }
        }
      }

      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        switch (statuses[i]) {
          case _RefStatus.unused:
            // Detection fix: an enum value reached only through `.values`
            // iteration (never a direct `EnumType.value` reference) is used,
            // not dead — do not report it at all.
            if (candidate.isEnumValue &&
                candidate.container != null &&
                enumValuesIterated.contains(
                  _key(candidate.path, candidate.container!),
                )) {
              break;
            }
            unused.add(_toUnused(candidate, rootPath));
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
      if (_shouldConsider(symbol, parentIsEnum, lines, symbols)) {
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

  bool _shouldConsider(
    DocumentSymbol symbol,
    bool parentIsEnum,
    List<String> lines,
    List<DocumentSymbol> siblings,
  ) {
    if (!options.kinds.contains(_reportedKind(symbol, parentIsEnum))) {
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
    // A used `call` method is unresolvable through implicit-call syntax, the
    // same way a used operator is unresolvable through infix syntax. Always
    // skipped; there's no flag for this one.
    if (_isCallMethod(symbol)) {
      return false;
    }
    // The classic prevent-instantiation marker — a class's *sole*,
    // *zero-parameter* private constructor (`Foo._();`) — is deliberately
    // never referenced. It is not dead code, and removing it would re-add the
    // implicit default constructor and silently make the class publicly
    // instantiable, so it is skipped. Other private constructors (named
    // alongside siblings, or taking parameters) can be genuinely dead and are
    // reported normally.
    if (_isPreventInstantiationMarker(symbol, siblings)) {
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

  /// The kind ciach reports for [symbol]. The analysis server tags enum
  /// values with [SymbolKind.enum$] — the same kind as the enum type itself —
  /// so remap them to [SymbolKind.enumMember] when they appear directly under
  /// an enum, matching the `enum-value` kind exposed on the command line.
  static SymbolKind _reportedKind(DocumentSymbol symbol, bool parentIsEnum) =>
      parentIsEnum && symbol.kind == .enum$ ? .enumMember : symbol.kind;

  UnusedDeclaration _toUnused(_Candidate candidate, String rootPath) {
    final symbol = candidate.symbol;
    final start = symbol.selectionRange.start;
    final name = _declarationName(symbol, candidate.container);
    return .new(
      name: name,
      kind: _reportedKind(symbol, candidate.isEnumValue),
      filePath: p.split(p.relative(candidate.path, from: rootPath)).join('/'),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      isPrivate: _isPrivateName(name),
      container: candidate.container,
      isEnumValue: candidate.isEnumValue,
      range: (
        startLine: symbol.range.start.line,
        startColumn: symbol.range.start.character,
        endLine: symbol.range.end.line,
        endColumn: symbol.range.end.character,
      ),
    );
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
    var top = symbol.range.start.line <= nameLine
        ? symbol.range.start.line
        : nameLine;

    // Extend upward across contiguous annotation / comment / blank lines so we
    // catch annotations placed above the modifier line.
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

  /// Classifies a candidate from the references reported for it: any real
  /// (non-doc) reference means used, only doc-comment links means doc-only,
  /// none means unused.
  _RefStatus _classify(List<Location> refs) {
    if (refs.isEmpty) {
      return _RefStatus.unused;
    }
    final hasRealRef = refs.any((loc) => !_isDocReference(loc));
    return hasRealRef ? _RefStatus.used : _RefStatus.docOnly;
  }

  /// Builds the map key pairing a file [path] with a declaration [name].
  static _DeclKey _key(String path, String name) => (path: path, name: name);

  /// Whether reference [loc] is the enum type's static `.values` getter — i.e.
  /// the referenced type name is immediately followed by `.values`. When an
  /// enum's `.values` is referenced anywhere, every value is reachable through
  /// iteration, so none of them is unused (the enum-`.values` detection fix).
  ///
  /// This covers the *qualified* form `<EnumName>.values`; the *implicit* form
  /// (a bare `values` inside the enum's own body, e.g. a `values.any(…)` helper)
  /// is caught by [_enumIteratesOwnValues] instead. Precise on purpose: only
  /// `<EnumName>.values` counts, not a `.value` access to some individual value,
  /// nor a `.values` on a different symbol.
  bool _isDotValuesRef(Location loc) {
    final located = _locateTypeToken(loc);
    if (located == null) {
      return false;
    }
    final (:tokens, :ti) = located;
    if (ti + 2 >= tokens.length) {
      return false;
    }
    final dot = tokens[ti + 1];
    final values = tokens[ti + 2];
    return !dot.isWord &&
        dot.value == '.' &&
        values.isWord &&
        values.value == 'values';
  }

  /// Whether the enum type [enumCandidate] iterates its own values through the
  /// implicit static `values` getter from *inside its own body* — a bare
  /// `values` identifier (not `x.values` member access on some receiver), as in
  /// a static/instance helper like `values.any((v) => …)`. Such a reference
  /// keeps every value alive but, having no `<EnumName>.` prefix, is invisible
  /// to a `textDocument/references` query on the enum *type* (see
  /// [_isDotValuesRef]), so it is detected here by a source scan.
  ///
  /// Conservative by construction: a local/parameter coincidentally named
  /// `values` would also match, keeping the enum's values — which only ever
  /// *retains* code, never removes something live.
  bool _enumIteratesOwnValues(_Candidate enumCandidate) {
    final content = _contentFor(enumCandidate.path);
    if (content.isEmpty) {
      return false;
    }
    final lineStarts = _lineStartsFor(enumCandidate.path);
    final startOff = _offsetOfPosition(
      lineStarts,
      content,
      enumCandidate.symbol.range.start,
    );
    final endOff = _offsetOfPosition(
      lineStarts,
      content,
      enumCandidate.symbol.range.end,
    );
    if (startOff == null || endOff == null) {
      return false;
    }
    final tokens = _tokensFor(enumCandidate.path);
    for (var i = 0; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.start < startOff) {
        continue;
      }
      if (t.start >= endOff) {
        break;
      }
      if (!t.isWord || t.value != 'values') {
        continue;
      }
      // A `.values` here is a member access on some other receiver, not the
      // enum's own implicit static getter; the qualified `<EnumName>.values`
      // form is handled by [_isDotValuesRef].
      final prev = i > 0 ? tokens[i - 1] : null;
      if (prev != null && !prev.isWord && prev.value == '.') {
        continue;
      }
      return true;
    }
    return false;
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
