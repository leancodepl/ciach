/// `// ciach:ignore` comments, which keep declarations from being reported.
library;

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/extensions.dart';

/// The marker comment that keeps the declaration on the next line, or on its
/// own line when it trails code.
const ignoreMarker = 'ciach:ignore';

/// The marker comment that keeps every declaration in the file.
const ignoreFileMarker = 'ciach:ignore-file';

/// The marker comments that open and close a range of kept declarations.
const ignoreStartMarker = 'ciach:ignore-start';
const ignoreEndMarker = 'ciach:ignore-end';

/// A `// ciach:<word>` comment; the word is checked against the markers.
final _marker = RegExp(r'^//\s*(ciach:[\w-]+)(?=\s|$)');

/// A marker comment and its zero-based line.
typedef MarkerAt = ({int line, String marker});

/// A malformed or misplaced marker: its zero-based line and what is wrong.
typedef MarkerIssue = ({int line, String message});

/// The `// ciach:` markers of one file. Only `//` comments count: a marker in
/// a doc comment, a block comment or a string is plain text.
final class IgnoreMarkers {
  IgnoreMarkers._({
    required this.ignoresFile,
    required List<int> nextLine,
    required List<int> sameLine,
    required List<(int, int)> ranges,
    required this.issues,
  }) : _nextLine = nextLine,
       _sameLine = sameLine,
       _ranges = ranges;

  factory IgnoreMarkers.parse(String content) {
    if (!content.contains('ciach:')) {
      return none;
    }
    var ignoresFile = false;
    final nextLine = <int>[];
    final sameLine = <int>[];
    final ranges = <(int, int)>[];
    final issues = <MarkerIssue>[];
    int? openedAt;
    final lines = content.split('\n');
    final code = stripComments(content).split('\n');
    for (final (line, text) in lines.indexed) {
      final (:comment, :ownLine) = _lineComment(text, code[line]);
      final marker = comment?.let(_marker.firstMatch)?.group(1);
      switch (marker) {
        case null:
          continue;
        case ignoreFileMarker:
          ignoresFile = true;
        case ignoreMarker when ownLine:
          nextLine.add(line);
        case ignoreMarker:
          sameLine.add(line);
        case ignoreStartMarker:
          if (openedAt != null) {
            issues.add((
              line: line,
              message:
                  '`// $ignoreStartMarker` inside the range opened on line ${openedAt + 1}',
            ));
          } else {
            openedAt = line;
          }
        case ignoreEndMarker:
          if (openedAt == null) {
            issues.add((
              line: line,
              message:
                  '`// $ignoreEndMarker` without a `// $ignoreStartMarker`',
            ));
          } else {
            ranges.add((openedAt, line));
            openedAt = null;
          }
        default:
          issues.add((
            line: line,
            message:
                'unknown marker `$marker`; the markers are $ignoreMarker, $ignoreFileMarker, $ignoreStartMarker and $ignoreEndMarker',
          ));
      }
    }
    if (openedAt != null) {
      ranges.add((openedAt, lines.length));
      issues.add((
        line: openedAt,
        message:
            '`// $ignoreStartMarker` without a `// $ignoreEndMarker`; it runs to the end of the file',
      ));
    }
    return ._(
      ignoresFile: ignoresFile,
      nextLine: nextLine,
      sameLine: sameLine,
      ranges: ranges,
      issues: issues,
    );
  }

  /// A file without markers.
  static final none = IgnoreMarkers._(
    ignoresFile: false,
    nextLine: const [],
    sameLine: const [],
    ranges: const [],
    issues: const [],
  );

  /// Whether a `// ciach:ignore-file` marker keeps the whole file.
  final bool ignoresFile;

  /// The markers that are malformed or out of place.
  final List<MarkerIssue> issues;

  /// Lines of `// ciach:ignore` comments that stand on their own.
  final List<int> _nextLine;

  /// Lines of `// ciach:ignore` comments that trail code.
  final List<int> _sameLine;

  /// `ciach:ignore-start` and `ciach:ignore-end` lines, an unclosed range
  /// ending past the last line.
  final List<(int, int)> _ranges;

  /// Whether this file has markers for single declarations or ranges.
  bool get isEmpty => _nextLine.isEmpty && _sameLine.isEmpty && _ranges.isEmpty;

  /// The marker that keeps a declaration whose doc comment and annotations
  /// start on [start] and whose name is on [nameLine], both zero-based; `null`
  /// when none does.
  ///
  /// A marker on its own line keeps the declaration that starts on the next
  /// line, or one whose doc comment or annotations it sits among; a trailing
  /// one, the declaration named on its line; a range, every declaration named
  /// inside it.
  MarkerAt? keeping({required int start, required int nameLine}) {
    for (final line in _nextLine) {
      if (line >= start - 1 && line < nameLine) {
        return (line: line, marker: ignoreMarker);
      }
    }
    if (_sameLine.contains(nameLine)) {
      return (line: nameLine, marker: ignoreMarker);
    }
    for (final (open, close) in _ranges) {
      if (open < nameLine && nameLine < close) {
        return (line: open, marker: ignoreStartMarker);
      }
    }
    return null;
  }

  /// The single-declaration markers and range starts, for telling which kept
  /// nothing.
  Iterable<MarkerAt> get all => [
    for (final line in _nextLine) (line: line, marker: ignoreMarker),
    for (final line in _sameLine) (line: line, marker: ignoreMarker),
    for (final (open, _) in _ranges) (line: open, marker: ignoreStartMarker),
  ];

  /// The `//` comment [text] holds, if any, and whether it is all the line
  /// holds besides whitespace. [code] is [text] with comments blanked.
  static ({String? comment, bool ownLine}) _lineComment(
    String text,
    String code,
  ) {
    for (var i = 0; i < text.length; i++) {
      if (text[i] == code[i]) {
        continue;
      }
      // A comment begins here; a block comment or a doc comment is no marker.
      final comment = text.substring(i);
      return comment.startsWith('//') && !comment.startsWith('///')
          ? (comment: comment, ownLine: code.substring(0, i).trim().isEmpty)
          : (comment: null, ownLine: false);
    }
    return (comment: null, ownLine: false);
  }
}
