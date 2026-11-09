/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:collection/collection.dart';

/// The UTF-16 code unit of `\n`.
const _lineFeed = 0x0A;

/// The offset at which each line of [content] starts. A line ends at `\n`,
/// also in `\r\n`, as the analyzer's scanner counts lines.
List<int> lineStartsOf(String content) => [
  0,
  for (final (i, unit) in content.codeUnits.indexed)
    if (unit == _lineFeed) i + 1,
];

/// The zero-based line and column of [offset] in content whose lines start
/// at [lineStarts].
({int line, int column}) positionIn(List<int> lineStarts, int offset) {
  final line = lowerBound(lineStarts, offset + 1) - 1;
  return (line: line, column: offset - lineStarts[line]);
}
