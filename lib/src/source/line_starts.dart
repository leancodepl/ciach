/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// The UTF-16 code unit of `\n`.
const _lineFeed = 0x0A;

/// The offset at which each line of [content] starts.
List<int> lineStartsOf(String content) => [
  0,
  for (final (i, unit) in content.codeUnits.indexed)
    if (unit == _lineFeed) i + 1,
];

/// The LSP position of [offset] in content whose lines start at [lineStarts].
Position positionIn(List<int> lineStarts, int offset) {
  final line = lowerBound(lineStarts, offset + 1) - 1;
  return .new(line: line, character: offset - lineStarts[line]);
}
