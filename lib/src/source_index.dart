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

import 'package:ciach/src/lexing.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Position;

/// A `[start, end)` slice of a file's token stream: the full token list plus
/// the index bounds of the tokens covered. Callers iterate `[start, end)` but
/// may still peek neighbours (`tokens[end]`, `tokens[start - 1]`).
typedef TokenWindow = ({List<Token> tokens, int start, int end});

/// Lazily-computed, per-file view of the source under analysis: its lines,
/// content, line-start offsets, and token stream, each cached on first use.
///
/// Everything the finder needs to translate an LSP [Position] into a byte
/// offset or a token, without re-reading or re-lexing a file, lives here.
class SourceIndex {
  final _lines = <String, List<String>>{};
  final _content = <String, String>{};
  final _lineStarts = <String, List<int>>{};
  final _tokens = <String, List<Token>>{};

  /// The absolute file path a reference [uri] points at.
  static String pathOf(String uri) => Uri.parse(uri).toFilePath();

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

  /// Records the [lines] of a file already opened in the analysis server, so
  /// its content isn't re-read from disk.
  void cacheLines(String path, List<String> lines) => _lines[path] = lines;

  /// The full text of [path], reconstructed from the cached lines so it matches
  /// the document content the analysis server resolved positions against.
  String content(String path) => _content[path] ??= lines(path).join('\n');

  List<int> lineStarts(String path) =>
      _lineStarts[path] ??= computeLineStarts(content(path));

  List<Token> tokens(String path) => _tokens[path] ??= tokenize(content(path));

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

  /// The token index whose span starts exactly at [position] in [path], or
  /// `null` if the position doesn't line up with a token start.
  int? tokenIndexAtPosition(String path, Position position) {
    final offset = offsetOf(path, position);
    return offset == null ? null : tokenIndexAt(tokens(path), offset);
  }

  /// The window of tokens in [path] whose start offset falls within [symbol]'s
  /// full source range, or `null` if the range can't be resolved. Unifies the
  /// "scan the tokens inside this declaration" preamble shared by the
  /// structural detectors.
  TokenWindow? tokenWindow(String path, DocumentSymbol symbol) {
    if (content(path).isEmpty) {
      return null;
    }
    final startOff = offsetOf(path, symbol.range.start);
    final endOff = offsetOf(path, symbol.range.end);
    if (startOff == null || endOff == null) {
      return null;
    }
    final toks = tokens(path);
    return (
      tokens: toks,
      start: _lowerBoundStart(toks, startOff),
      end: _lowerBoundStart(toks, endOff),
    );
  }

  /// The index of the first token whose start offset is `>= offset` (tokens are
  /// ordered by start), i.e. the lower bound for a range scan.
  static int _lowerBoundStart(List<Token> tokens, int offset) {
    var lo = 0;
    var hi = tokens.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (tokens[mid].start < offset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }
}
