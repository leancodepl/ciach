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
    (open: _marker(open), close: _marker(close)),
];

RegExp _marker(String marker) =>
    RegExp('^//\\s*${RegExp.escape(marker)}(?![\\w-])', caseSensitive: false);

/// The spans of the range markers in [content] that are left around nothing
/// but whitespace and comments.
///
/// A marker on its own line spans the whole line; one after code spans the
/// blanks before it.
List<({int start, int end})> emptyRangeMarkers(String content) {
  final comments = lineComments(content).toList();
  final code = stripComments(content);
  return [
    for (final pair in _pairs)
      for (final (open, close) in _matched(content, comments, pair))
        if (code.substring(open.end, close.offset).trim().isEmpty) ...[
          open.span,
          close.span,
        ],
  ];
}

/// Each [pair] marker in [comments] that opens a range, with the one that
/// closes it.
Iterable<(_Marker, _Marker)> _matched(
  String content,
  List<({int offset, String text})> comments,
  ({RegExp open, RegExp close}) pair,
) sync* {
  final opened = <({int offset, String text})>[];
  for (final comment in comments) {
    if (pair.open.hasMatch(comment.text)) {
      opened.add(comment);
    } else if (pair.close.hasMatch(comment.text) && opened.isNotEmpty) {
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
