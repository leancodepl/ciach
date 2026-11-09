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
final class Position implements Comparable<Position> {
  const Position({required this.line, required this.character});

  final int line;
  final int character;

  /// Orders positions by line, then by column.
  @override
  int compareTo(Position other) => switch (line.compareTo(other.line)) {
    0 => character.compareTo(other.character),
    final byLine => byLine,
  };

  /// Whether this position is before [other].
  bool isBefore(Position other) => compareTo(other) < 0;

  /// Whether this position is at or before [other].
  bool atOrBefore(Position other) => compareTo(other) <= 0;

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

/// A [range] in the file at [path].
final class Location {
  const Location({required this.path, required this.range});

  /// The absolute path of the file, such as `/home/me/app/lib/main.dart`.
  final String path;
  final Range range;

  /// Orders locations by file, then by where they start.
  static int byPlace(Location a, Location b) =>
      switch (a.path.compareTo(b.path)) {
        0 => a.range.start.compareTo(b.range.start),
        final byFile => byFile,
      };

  @override
  bool operator ==(Object other) =>
      other is Location && other.path == path && other.range == range;

  @override
  int get hashCode => Object.hash(path, range);

  @override
  String toString() => 'Location(path: $path, range: $range)';
}
