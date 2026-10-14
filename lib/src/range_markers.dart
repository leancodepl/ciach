/// Comments that open and close a range of code for a tool, and the pairs of
/// them left around nothing.
library;

import 'package:ciach/src/comment_stripping.dart';

/// The markers that open and close a range: coverage, ciach, the formatter and
/// the spell checker.
final _pairs = [
  for (final (open, close) in const [
    ('coverage:ignore-start', 'coverage:ignore-end'),
    ('ciach:ignore-start', 'ciach:ignore-end'),
    ('dart format off', 'dart format on'),
    ('cspell:disable', 'cspell:enable'),
  ])
    (
      open: open,
      close: close,
      openPattern: _marker(open),
      closePattern: _marker(close),
    ),
];

RegExp _marker(String marker) =>
    RegExp('^//\\s*${RegExp.escape(marker)}(?![\\w-])', caseSensitive: false);

/// A pair of range comments with nothing but whitespace and comments between
/// them: the opening comment's one-based line, the two markers, and the spans
/// that removing them deletes.
///
/// A marker on its own line spans the whole line; one after code spans the
/// blanks before it.
typedef EmptyRangeIn = ({
  int line,
  String open,
  String close,
  List<({int start, int end})> spans,
});

/// The empty ranges in [content].
List<EmptyRangeIn> emptyRanges(String content) {
  final comments = lineComments(content).toList();
  final code = stripComments(content);
  return [
    for (final pair in _pairs)
      for (final (open, close) in _matched(
        content,
        comments,
        pair.openPattern,
        pair.closePattern,
      ))
        if (code.substring(open.end, close.offset).trim().isEmpty)
          (
            line: '\n'.allMatches(content.substring(0, open.offset)).length + 1,
            open: pair.open,
            close: pair.close,
            spans: [open.span, close.span],
          ),
  ];
}

/// Each comment in [comments] that [open] matches, with the one that [close]
/// matches and closes its range.
Iterable<(_Marker, _Marker)> _matched(
  String content,
  List<({int offset, String text})> comments,
  RegExp open,
  RegExp close,
) sync* {
  final opened = <({int offset, String text})>[];
  for (final comment in comments) {
    if (open.hasMatch(comment.text)) {
      opened.add(comment);
    } else if (close.hasMatch(comment.text) && opened.isNotEmpty) {
      yield (_Marker(content, opened.removeLast()), _Marker(content, comment));
    }
  }
}

/// A marker comment placed in its line.
final class _Marker {
  _Marker(String content, ({int offset, String text}) comment)
    : offset = comment.offset,
      end = comment.offset + comment.text.length,
      lineStart = comment.offset == 0
          ? 0
          : content.lastIndexOf('\n', comment.offset - 1) + 1,
      _content = content;

  final String _content;

  final int offset;

  /// Just past the comment.
  final int end;

  final int lineStart;

  bool get ownLine => _content.substring(lineStart, offset).trim().isEmpty;

  /// What removing the marker deletes.
  ({int start, int end}) get span {
    if (ownLine) {
      return (start: lineStart, end: end < _content.length ? end + 1 : end);
    }
    var start = offset;
    while (start > lineStart && _content[start - 1].trim().isEmpty) {
      start--;
    }
    return (start: start, end: end);
  }
}
