/// Character-offset spans in a file's text, the whitespace arithmetic that
/// keeps a deletion tidy, and the comments of other tools, which tell what a
/// deletion takes along.
library;

import 'dart:math';

import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// A `[start, end)` character-offset span within a file's content.
typedef Span = ({int start, int end});

List<Span> mergeSpans(List<Span> spans) {
  final merged = <Span>[];
  for (final span in spans.sortedBy<num>((s) => s.start)) {
    if (merged.isNotEmpty && span.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((start: last.start, end: max(span.end, last.end)));
    } else {
      merged.add(span);
    }
  }
  return merged;
}

/// [offset], moved to the start of its line in [content] when only
/// indentation precedes it.
int withIndentation(String content, int offset) {
  final lineStart = offset == 0 ? 0 : content.lastIndexOf('\n', offset - 1) + 1;
  return content.substring(lineStart, offset).trim().isEmpty
      ? lineStart
      : offset;
}

/// If nothing but whitespace, or a `//` comment, follows [end] on its line,
/// extends it past the line break — so deleting a declaration leaves neither a
/// blank line nor its trailing comment behind. That comment, such as an
/// `// ignore:`, would otherwise apply to the line after it. Any other tool
/// directive stays, so a range it opens or closes keeps both ends.
int consumeLineEnd(String content, int end) {
  final nextNewline = content.indexOfOrNull('\n', end);
  final restOfLine = content.substring(end, nextNewline ?? content.length);
  if (nextNonWhitespace(restOfLine, 0) case final i?) {
    final comment = restOfLine.substring(i);
    if (!comment.startsWith('//') ||
        (isToolDirective(comment) && !isNextLineDirective(comment))) {
      return end;
    }
  }
  return nextNewline?.let((newline) => newline + 1) ?? content.length;
}

/// Skips spaces and tabs from [from], but never across a line break.
int skipSameLineBlank(String content, int from) {
  var i = from;
  while (i < content.length && isSpaceOrTab(content[i])) {
    i++;
  }
  return i;
}

/// Whether [ch] is a space or tab — a blank that stays on the same line.
bool isSpaceOrTab(String ch) => switch (ch) {
  ' ' || '\t' => true,
  _ => false,
};

/// Whether [comment] applies to the next line only: an analyzer
/// `// ignore:`, a custom_lint `// expect_lint:` or a spell checker's
/// `// cspell:disable-next-line`.
bool isNextLineDirective(String comment) =>
    _nextLineDirective.hasMatch(comment);

final _nextLineDirective = RegExp(
  r'^//\s*(ignore:|expect_lint:|(cspell|spell-checker):\s*disable-next-line)',
  caseSensitive: false,
);

/// A comment another tool reads, such as `// coverage:ignore-start`,
/// `// ciach:ignore-end` or `// dart format off`. It may pair with a comment
/// elsewhere in the file.
bool isToolDirective(String comment) => _toolDirective.hasMatch(comment);

final _toolDirective = RegExp(r'^//\s*([\w.-]+:\S|dart format\b)');

/// The index of the first non-whitespace character at or after [from], if
/// any.
int? nextNonWhitespace(String content, int from) {
  for (var i = from; i < content.length; i++) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

/// The index of the last non-whitespace character before [before], if any.
int? previousNonWhitespace(String content, int before) {
  for (var i = before - 1; i >= 0; i--) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

bool _isWhitespace(String ch) => switch (ch) {
  ' ' || '\t' || '\n' || '\r' => true,
  _ => false,
};
