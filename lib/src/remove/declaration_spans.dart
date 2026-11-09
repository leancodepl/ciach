/// The span to delete for a declaration that the outline covers whole: a
/// class, function, method, property or enum value.
library;

import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/remove/text_spans.dart';

/// Computes the span to delete in [content] for an enum value, when
/// [isEnumValue], or a "whole-node" kind (class, function, method, property,
/// …) whose [range] already covers the full declaration. Deletion starts at
/// [fullRange], which adds the doc comment and annotations.
Span spanFor(
  String content,
  DeclarationRange range,
  DeclarationRange fullRange, {
  required bool isEnumValue,
}) {
  final baseEnd = range.end;
  final fullStart = withIndentation(content, fullRange.start);

  var start = fullStart;
  var end = baseEnd;

  if (isEnumValue) {
    (:start, :end) = _extendEnumValue(
      content,
      valueStart: fullStart,
      baseEnd: baseEnd,
    );
  } else if (end < content.length && content[end] == ';') {
    // Some whole-node kinds (bodyless constructors, arrow-bodied members)
    // don't include their terminating `;` in the range.
    end++;
  }

  return (start: start, end: consumeLineEnd(content, end));
}

/// Enum values are comma-separated, not self-terminating: dropping one
/// without also dropping a neighboring comma leaves invalid syntax. Prefers
/// consuming a trailing comma (keeps the shape for the common
/// trailing-comma style); falls back to the leading comma for the last value
/// in a list without one.
Span _extendEnumValue(
  String content, {
  required int valueStart,
  required int baseEnd,
}) {
  final forward = nextNonWhitespace(content, baseEnd);
  if (forward != null && content[forward] == ',') {
    // Swallow the blank after the comma too, but stop at a line break so a
    // multi-line enum's indentation stays intact.
    return (start: valueStart, end: skipSameLineBlank(content, forward + 1));
  }
  final backward = previousNonWhitespace(content, valueStart);
  if (backward != null && content[backward] == ',') {
    return (start: backward, end: baseEnd);
  }
  return (start: valueStart, end: baseEnd);
}

/// Drops the separator comma left dangling when a compact single-line enum
/// loses a trailing run of values — when the merged [span] is bracketed on its
/// own line by a leading `,` and a trailing `}`. Otherwise the comma is a real
/// separator and the span is returned unchanged; the same-line guards leave
/// multi-line enums untouched.
Span absorbOrphanEnumComma(String content, Span span) {
  final after = skipSameLineBlank(content, span.end);
  if (after >= content.length || content[after] != '}') {
    return span;
  }
  var before = span.start - 1;
  while (before >= 0 && isSpaceOrTab(content[before])) {
    before--;
  }
  if (before < 0 || content[before] != ',') {
    return span;
  }
  return (start: before, end: span.end);
}
