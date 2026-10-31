/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/line_starts.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, SelectionRange;

const _noSemanticTokens =
    'Could not read comments and annotations; findings may be missed.';

/// Per-file view of the source under analysis: its lines, content and line
/// starts, plus the server's semantic tokens and selection ranges, each cached
/// on first use.
class SourceIndex {
  final _lines = CachedMap<String, List<String>>(
    (path) => readFile(path)?.split('\n') ?? const [],
  );
  final _semanticTokens = <String, List<SemanticToken>>{};

  /// The requests for semantic tokens that have not answered yet, so that
  /// two callers that need the same file's tokens send one request.
  final _pendingSemanticTokens = <String, Future<List<SemanticToken>>>{};
  final _selectionRanges = <String, Map<(int, int), SelectionRange>>{};
  late final _content = CachedMap<String, String>(
    (path) => lines(path).join('\n'),
  );
  late final _lineStarts = CachedMap<String, List<int>>(
    (path) => lineStartsOf(content(path)),
  );
  final _scanned = <String>{};

  /// The absolute file path a reference [uri] points at.
  static String pathOf(String uri) => Uri.parse(uri).toFilePath();

  /// The files opened for this run — every path passed to [cacheLines].
  Iterable<String> get scannedPaths => _scanned;

  /// Reads [path] from disk, returning `null` if it can't be read.
  static String? readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// The lines of the file at [path], read (and cached) on demand.
  List<String> lines(String path) => _lines[path];

  void cacheSemanticTokens(String path, List<SemanticToken> tokens) {
    _semanticTokens[path] = tokens;
  }

  List<SemanticToken>? semanticTokens(String path) => _semanticTokens[path];

  /// Returns the semantic tokens of [path], which [client] sends the first
  /// time they are needed, or an empty list if the server has none. A file
  /// without tokens reads as all code, which only keeps declarations.
  Future<List<SemanticToken>> semanticTokensOf(
    LspClient client,
    String path,
  ) async {
    if (_semanticTokens[path] case final tokens?) {
      return tokens;
    }
    final pending = _pendingSemanticTokens[path] ??= _requestSemanticTokens(
      client,
      path,
    );
    return await pending;
  }

  /// Requests the semantic tokens of [path] from [client] and caches them.
  Future<List<SemanticToken>> _requestSemanticTokens(
    LspClient client,
    String path,
  ) async {
    try {
      final tokens = await client.semanticTokens(File(path).uri, lines(path));
      return _semanticTokens[path] = tokens;
    } on LspRequestException catch (e) {
      recordProblem(_noSemanticTokens, e, path: path);
      return _semanticTokens[path] = const [];
    }
  }

  bool hasSemanticTokens(String path) => _semanticTokens.containsKey(path);

  void cacheSelectionRange(
    String path,
    Position position,
    SelectionRange selectionRange,
  ) {
    _selectionRanges.putIfAbsent(
      path,
      () => {},
    )[(position.line, position.character)] = selectionRange;
  }

  /// The syntax nodes enclosing [position] in [path], innermost first.
  SelectionRange? selectionRangeAt(String path, Position position) =>
      _selectionRanges[path]?[(position.line, position.character)];

  /// The tokens of [outline]'s doc comment and annotations.
  Iterable<SemanticToken> leadingMetadata(String path, Outline outline) =>
      semanticTokens(
        path,
      )?.between(outline.range.start, outline.codeRange.start) ??
      const [];

  /// Records the [lines] of a file already opened in the analysis server, so
  /// its content isn't re-read from disk, and marks the file as scanned.
  void cacheLines(String path, List<String> lines) {
    _lines[path] = lines;
    _content.invalidate(path);
    _lineStarts.invalidate(path);
    _scanned.add(path);
  }

  /// The full text of [path], reconstructed from the cached lines so it matches
  /// the document content the analysis server resolved positions against.
  String content(String path) => _content[path];

  List<int> lineStarts(String path) => _lineStarts[path];

  /// The LSP position of [offset] in [path]'s content.
  Position positionOf(String path, int offset) =>
      positionIn(lineStarts(path), offset);

  /// Absolute offset of an LSP [position] in [path]'s content, or `null` if out
  /// of range. LSP columns are UTF-16 code units, which is exactly how Dart
  /// indexes a `String`, so the arithmetic needs no conversion.
  int? offsetOf(String path, Position position) {
    final starts = lineStarts(path);
    if (position.line < 0 || position.line >= starts.length) {
      return null;
    }
    final offset = starts[position.line] + position.character;
    if (offset < 0 || offset > content(path).length) {
      return null;
    }
    return offset;
  }
}
