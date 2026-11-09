/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/source/line_starts.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:path/path.dart' as p;

/// A location as the tests compare it: the file, relative to the directory
/// that a test wrote, the one-based line, and the text that it covers.
typedef LocationText = ({String file, int line, String text});

/// Returns [location] as the tests compare it, with its file relative to
/// [root].
LocationText locationText(Location location, String root) {
  final line = File(location.path).readAsLinesSync()[location.range.start.line];
  return (
    file: p.relative(location.path, from: root),
    line: location.range.start.line + 1,
    text: line.substring(
      location.range.start.character,
      location.range.end.character,
    ),
  );
}

/// Returns the position of the [occurrence]th [name] in the file at [path],
/// counting from 0.
Position positionOfName(String path, String name, {int occurrence = 0}) {
  final source = File(path).readAsStringSync();
  final offset = name.allMatches(source).elementAt(occurrence).start;
  return positionIn(lineStartsOf(source), offset);
}

/// Returns the text of [source] that [range] covers.
String textIn(String source, Range range) {
  final starts = lineStartsOf(source);
  int offsetOf(Position position) => starts[position.line] + position.character;
  return source.substring(offsetOf(range.start), offsetOf(range.end));
}
