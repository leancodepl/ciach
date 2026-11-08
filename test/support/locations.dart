/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/source/locations.dart';
import 'package:path/path.dart' as p;

/// A location as the tests compare it: the file, relative to the directory
/// that a test wrote, the one-based line, and the text that it covers.
typedef LocationText = ({String file, int line, String text});

/// Returns [location] as the tests compare it, with its file relative to
/// [root].
LocationText locationText(Location location, String root) {
  final path = Uri.parse(location.uri).toFilePath();
  final line = File(path).readAsLinesSync()[location.range.start.line];
  return (
    file: p.relative(path, from: root),
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
  var offset = source.indexOf(name);
  for (var i = 0; i < occurrence; i++) {
    offset = source.indexOf(name, offset + 1);
  }
  final before = source.substring(0, offset);
  return .new(
    line: '\n'.allMatches(before).length,
    character: offset - (before.lastIndexOf('\n') + 1),
  );
}
