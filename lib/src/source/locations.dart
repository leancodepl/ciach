/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Places in source text: a [Range] of offsets, and a [Location], which is
/// a range in a file.
library;

/// The text from offset [start] to offset [end] in a file's content. Offsets
/// count UTF-16 code units, as Dart strings do.
final class Range {
  const Range({required this.start, required this.end});

  final int start;
  final int end;

  /// Whether [offset] lies within this range, both ends included.
  bool contains(int offset) => start <= offset && offset <= end;

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
