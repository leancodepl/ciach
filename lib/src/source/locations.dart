/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Places in source text: a [Position], a [Range] between two positions, and
/// a [Location], which is a range in a file.
library;

/// A place in source text: a zero-based line, and a zero-based column in UTF-16
/// code units, which is how Dart strings count characters.
final class Position {
  const Position({required this.line, required this.character});

  final int line;
  final int character;

  @override
  bool operator ==(Object other) =>
      other is Position && other.line == line && other.character == character;

  @override
  int get hashCode => Object.hash(line, character);

  @override
  String toString() => 'Position(line: $line, character: $character)';
}

/// The text between [start] and [end].
final class Range {
  const Range({required this.start, required this.end});

  final Position start;
  final Position end;

  @override
  bool operator ==(Object other) =>
      other is Range && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'Range(start: $start, end: $end)';
}

/// A [range] in the file at [uri].
final class Location {
  const Location({required this.uri, required this.range});

  /// The file URI, such as `file:///home/me/app/lib/main.dart`.
  final String uri;
  final Range range;

  @override
  bool operator ==(Object other) =>
      other is Location && other.uri == uri && other.range == range;

  @override
  int get hashCode => Object.hash(uri, range);

  @override
  String toString() => 'Location(uri: $uri, range: $range)';
}
