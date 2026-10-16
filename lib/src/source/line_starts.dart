/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// The offset at which each line of [content] starts.
List<int> lineStartsOf(String content) => [
  0,
  for (var i = 0; i < content.length; i++)
    if (content[i] == '\n') i + 1,
];

/// The LSP position of [offset] in content whose lines start at [lineStarts].
Position positionIn(List<int> lineStarts, int offset) {
  final line = lowerBound(lineStarts, offset + 1) - 1;
  return .new(line: line, character: offset - lineStarts[line]);
}
