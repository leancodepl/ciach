/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/source/locations.dart';

extension LinePositions on LineInfo {
  /// The position of [offset]. The analyzer counts lines and columns from 1,
  /// a [Position] from 0.
  Position positionOf(int offset) {
    final location = getLocation(offset);
    return .new(
      line: location.lineNumber - 1,
      character: location.columnNumber - 1,
    );
  }

  /// The range from [start] to [end].
  Range rangeOf(int start, int end) =>
      .new(start: positionOf(start), end: positionOf(end));

  /// The location of the [length] characters at [offset] in the file at
  /// [path], whose lines this holds.
  Location locationOf(String path, int offset, int length) =>
      .new(path: path, range: rangeOf(offset, offset + length));
}
