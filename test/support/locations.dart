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
  final source = File(location.path).readAsStringSync();
  return (
    file: p.relative(location.path, from: root),
    line: positionIn(lineStartsOf(source), location.range.start).line + 1,
    text: textIn(source, location.range),
  );
}

/// Returns the offset of the [occurrence]th [name] in the file at [path],
/// counting from 0.
int offsetOfName(String path, String name, {int occurrence = 0}) =>
    name.allMatches(File(path).readAsStringSync()).elementAt(occurrence).start;

/// Returns the text of [source] that [range] covers.
String textIn(String source, Range range) =>
    source.substring(range.start, range.end);
