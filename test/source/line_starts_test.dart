/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/line_starts.dart';
import 'package:test/test.dart';

void main() {
  test(r'lineStartsOf starts a line after `\n` and after `\r\n`', () {
    expect(lineStartsOf(['a', '\n', 'b', '\r\n', 'c'].join()), [0, 2, 5]);
  });

  test('positionIn gives the zero-based line and column of an offset', () {
    final starts = lineStartsOf('ab\ncd');

    expect(
      [positionIn(starts, 0), positionIn(starts, 2), positionIn(starts, 4)],
      [(line: 0, column: 0), (line: 0, column: 2), (line: 1, column: 1)],
    );
  });
}
