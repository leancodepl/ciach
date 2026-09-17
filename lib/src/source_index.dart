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

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, SelectionRange;

/// Per-file view of the source under analysis: its lines, content and line
/// starts, plus the server's semantic tokens and selection ranges, each cached
/// on first use.
class SourceIndex {
  final _lines = <String, List<String>>{};
  final _semanticTokens = <String, List<SemanticToken>>{};
  final _selectionRanges = <String, Map<(int, int), SelectionRange>>{};
  final _content = <String, String>{};
  final _lineStarts = <String, List<int>>{};
  final _scanned = <String>{};

  /// The absolute file path a reference [uri] points at.
  static String pathOf(String uri) => Uri.parse(uri).toFilePath();

  /// The files opened for this run — every path passed to [cacheLines].
  Iterable<String> get scannedPaths => _scanned;

  /// Reads [path] from disk, returning `null` if it can't be read.
  static String? readFile(String path) {
    try {
      return File(path).readAsStringSync();
    } on Object {
      return null;
    }
  }

  /// The lines of the file at [path], read (and cached) on demand.
  List<String> lines(String path) =>
      _lines[path] ??= readFile(path)?.split('\n') ?? const [];

  void cacheSemanticTokens(String path, List<SemanticToken> tokens) {
    _semanticTokens[path] = tokens;
  }

  List<SemanticToken>? semanticTokens(String path) => _semanticTokens[path];

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
    _scanned.add(path);
  }

  /// The full text of [path], reconstructed from the cached lines so it matches
  /// the document content the analysis server resolved positions against.
  String content(String path) => _content[path] ??= lines(path).join('\n');

  List<int> lineStarts(String path) =>
      _lineStarts[path] ??= _computeLineStarts(content(path));

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

  /// The start offset of each line in [content].
  static List<int> _computeLineStarts(String content) {
    final starts = <int>[0];
    for (var i = 0; i < content.length; i++) {
      if (content[i] == '\n') {
        starts.add(i + 1);
      }
    }
    return starts;
  }
}
