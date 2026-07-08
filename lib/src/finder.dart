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
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location, SymbolKind;

/// A declaration to check: the symbol plus enough context to query references
/// for it and to report it later.
typedef _Candidate = ({
  Uri uri,
  String path,
  DocumentSymbol symbol,
  String? container,
  bool isEnumValue,
});

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
    final path = Uri.parse(location.uri).toFilePath();
    final lines = _fileLines[path] ??= _readFile(path)?.split('\n') ?? const [];
    final line = location.range.start.line;
    if (line < 0 || line >= lines.length) {
      return false;
    }
    return lines[line].trim().startsWith('///');
  }

  void _report(String message) => options.onProgress?.call(message);

  /// Runs the analysis and returns the declarations that are never referenced.
  Future<FinderResult> run() async {
    final stopwatch = Stopwatch()..start();
    final rootPath = p.normalize(p.absolute(options.rootPath));

    final files = discoverDartFiles(options);
    _report('Discovered ${files.length} Dart file(s) to scan.');

    if (files.isEmpty) {
      return .new(
        unused: const [],
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
    var declarationsChecked = 0;

    try {
      await client.initialize(Directory(rootPath).uri);
      _report('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

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

      final isUnused = await _mapPooled<_Candidate, bool>(
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
          final realRefs = options.ignoreDocReferences
              ? refs.where((loc) => !_isDocReference(loc))
              : refs;
          return realRefs.isEmpty;
        },
      );

      for (var i = 0; i < candidates.length; i++) {
        if (isUnused[i]) {
          unused.add(_toUnused(candidates[i], rootPath));
        }
      }
    } finally {
      await client.dispose();
    }

    unused.sort(_byLocation);
    stopwatch.stop();
    return .new(
      unused: unused,
      filesScanned: files.length,
      declarationsChecked: declarationsChecked,
      elapsed: stopwatch.elapsed,
    );
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

  UnusedDeclaration _toUnused(_Candidate candidate, String rootPath) {
    final symbol = candidate.symbol;
    final start = symbol.selectionRange.start;
    final name = _declarationName(symbol, candidate.container);
    return .new(
      name: name,
      kind: symbol.kind,
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
