/// Character-offset spans in a file's text, and the whitespace arithmetic
/// that keeps a deletion tidy.
library;

import 'dart:math';

import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/comment_stripping.dart';
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

/// The start of [fullRange], moved to the start of its line when only
/// indentation precedes it.
int startWithIndentation(
  DeclarationRange fullRange,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final prefix = lines[fullRange.startLine].substring(0, fullRange.startColumn);
  return offsetOf(
    fullRange.startLine,
    prefix.trim().isEmpty ? 0 : fullRange.startColumn,
  );
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

/// Skips spaces and tabs from [from], but never across a line break — used to
/// consume the gap after a removed enum value's comma.
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
