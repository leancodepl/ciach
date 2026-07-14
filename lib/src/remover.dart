import 'dart:io';

import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

/// Symbol kinds whose [DeclarationRange] covers only the declarator (name and
/// initializer), not the shared `final`/`const`/type prefix or the
/// terminating `;` — because the analysis server reports a variable's range
/// as the `VariableDeclaration`, not the whole
/// `VariableDeclarationList`/`FieldDeclaration` statement it lives in.
const _declaratorKinds = <SymbolKind>{.field, .variable, .constant};

/// A `[start, end)` character-offset span within a file's content.
typedef _Span = ({int start, int end});

/// Deletes [declarations] from the files under [rootPath], rewriting each
/// affected file in a single pass.
///
/// Declarations whose range is fully contained within another declaration's
/// range (e.g. a method of a class that is itself unused) are removed once,
/// as part of removing the enclosing declaration. A declarator that shares a
/// statement with other, still-used declarators (e.g. `int a = 1, b = 2;`) is
/// only removed on its own when that can be done unambiguously; otherwise it
/// is left in place rather than risk producing invalid source.
///
/// Returns the number of files that were actually modified.
int removeDeclarations(List<UnusedDeclaration> declarations, String rootPath) {
  final byFile = <String, List<UnusedDeclaration>>{};
  for (final decl in declarations) {
    byFile.putIfAbsent(decl.filePath, () => []).add(decl);
  }

  var filesChanged = 0;
  for (final entry in byFile.entries) {
    final file = File(p.joinAll([rootPath, ...p.posix.split(entry.key)]));
    final content = file.readAsStringSync();
    final updated = _removeFromContent(content, entry.value);
    if (updated != content) {
      file.writeAsStringSync(updated);
      filesChanged++;
    }
  }
  return filesChanged;
}

String _removeFromContent(String content, List<UnusedDeclaration> decls) {
  final lines = content.split('\n');
  final lineStarts = List<int>.filled(lines.length, 0);
  for (var i = 1; i < lines.length; i++) {
    lineStarts[i] = lineStarts[i - 1] + lines[i - 1].length + 1;
  }
  int offsetOf(int line, int column) => lineStarts[line] + column;

  final declarators = <UnusedDeclaration>[];
  final spans = <_Span>[];
  final enumSpans = <_Span>[];
  for (final decl in decls) {
    if (_declaratorKinds.contains(decl.kind)) {
      declarators.add(decl);
    } else {
      final span = _spanFor(decl, content, lines, offsetOf);
      if (span != null) {
        (decl.isEnumValue ? enumSpans : spans).add(span);
      }
    }
  }
  // Merge the per-value spans of each enum first, then drop any separator
  // comma left orphaned when a trailing run of values is removed from a
  // compact single-line enum (e.g. `enum E { a, b, c }` losing `b` and `c`
  // must become `enum E { a }`, not `enum E { a, }`).
  for (final span in _mergeSpans(enumSpans)) {
    spans.add(_absorbOrphanEnumComma(content, span));
  }
  spans.addAll(_declaratorSpans(declarators, content, lines, offsetOf));

  if (spans.isEmpty) {
    return content;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in _mergeSpans(spans)) {
    buffer.write(content.substring(cursor, span.start));
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  return buffer.toString();
}

/// Computes the span to delete for an enum value or a "whole-node" kind
/// (class, function, method, property, …) whose [DeclarationRange] already
/// covers the full declaration.
_Span? _spanFor(
  UnusedDeclaration decl,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final range = decl.range;
  final baseStart = offsetOf(range.startLine, range.startColumn);
  final baseEnd = offsetOf(range.endLine, range.endColumn);
  final topLine = _extendedTopLine(range.startLine, lines);

  var start = baseStart;
  var end = baseEnd;

  if (decl.isEnumValue) {
    // The value's own start: reach up to column 0 to take its leading
    // doc-comment/annotation lines and indentation when it sits on its own
    // line(s), but never past other tokens sharing its line — the `enum E {`
    // and earlier values of a compact single-line `enum E { a, b, c }`, where
    // starting at column 0 would eat the declaration itself.
    var valueStart = topLine < range.startLine
        ? offsetOf(topLine, 0)
        : baseStart;
    if (valueStart == baseStart) {
      final prefix = lines[range.startLine].substring(0, range.startColumn);
      if (prefix.trim().isEmpty) {
        valueStart = offsetOf(range.startLine, 0);
      }
    }
    (start, end) = _extendEnumValue(
      content,
      valueStart: valueStart,
      baseStart: baseStart,
      baseEnd: baseEnd,
    );
  } else {
    start = topLine < range.startLine ? offsetOf(topLine, 0) : baseStart;
    // A whole-node range that shares its line with other content (unusual,
    // but possible) is left alone rather than risk eating it; otherwise its
    // leading indentation is safe to take too.
    if (start == baseStart) {
      final prefix = lines[range.startLine].substring(0, range.startColumn);
      if (prefix.trim().isEmpty) {
        start = offsetOf(range.startLine, 0);
      }
    }
    // Some whole-node kinds (bodyless constructors, arrow-bodied members)
    // don't include their terminating `;` in the range.
    if (end < content.length && content[end] == ';') {
      end++;
    }
  }

  return (start: start, end: _consumeTrailingBlankLine(content, end));
}

/// Computes the spans to delete for `field`/`variable`/`constant` decls,
/// which share a statement — and possibly a `final`/`const`/type prefix —
/// with any number of sibling declarators.
///
/// Declarators are grouped by the statement's terminating `;`. When every
/// declarator in a statement is present in [decls], the whole statement
/// (prefix, every declarator, and the `;`) is removed as one span; otherwise
/// each targeted declarator is trimmed out of the list individually.
List<_Span> _declaratorSpans(
  List<UnusedDeclaration> decls,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final groups = <int, List<UnusedDeclaration>>{};
  for (final decl in decls) {
    final baseEnd = offsetOf(decl.range.endLine, decl.range.endColumn);
    final statementEnd = _finalStatementEnd(content, baseEnd);
    if (statementEnd == null) {
      // Can't even find where the statement ends; leave it alone.
      continue;
    }
    groups.putIfAbsent(statementEnd, () => []).add(decl);
  }

  int startOf(UnusedDeclaration d) =>
      offsetOf(d.range.startLine, d.range.startColumn);

  final spans = <_Span>[];
  for (final entry in groups.entries) {
    final members = entry.value
      ..sort((a, b) => startOf(a).compareTo(startOf(b)));
    final whole = _wholeStatementSpan(
      content,
      lines,
      members,
      entry.key,
      offsetOf,
    );
    if (whole != null) {
      spans.add(whole);
      continue;
    }
    for (final decl in members) {
      final span = _partialDeclaratorSpan(decl, content, offsetOf);
      if (span != null) {
        spans.add(span);
      }
    }
  }
  return spans;
}

/// Whether every declarator of the statement ending at [statementEnd] is
/// present in [sortedMembers] (sorted by source position) — verified by
/// checking that nothing but a bare `,` separates consecutive members, that
/// nothing but whitespace follows the last one up to [statementEnd], and
/// that no earlier declarator precedes the first one on its line.
///
/// The last check assumes the statement's type/modifier prefix and its first
/// declarator share a line — true for any `dart format`-formatted source.
_Span? _wholeStatementSpan(
  String content,
  List<String> lines,
  List<UnusedDeclaration> sortedMembers,
  int statementEnd,
  int Function(int line, int column) offsetOf,
) {
  final first = sortedMembers.first;
  final lineStart = offsetOf(first.range.startLine, 0);
  final firstStart = offsetOf(first.range.startLine, first.range.startColumn);
  if (_lastTopLevelComma(content.substring(lineStart, firstStart)) != null) {
    return null;
  }

  for (var i = 0; i < sortedMembers.length - 1; i++) {
    final end = offsetOf(
      sortedMembers[i].range.endLine,
      sortedMembers[i].range.endColumn,
    );
    final nextStart = offsetOf(
      sortedMembers[i + 1].range.startLine,
      sortedMembers[i + 1].range.startColumn,
    );
    if (content.substring(end, nextStart).trim() != ',') {
      return null;
    }
  }

  final last = sortedMembers.last;
  final lastEnd = offsetOf(last.range.endLine, last.range.endColumn);
  if (content.substring(lastEnd, statementEnd).trim().isNotEmpty) {
    return null;
  }

  final topLine = _extendedTopLine(first.range.startLine, lines);
  return (
    start: offsetOf(topLine, 0),
    end: _consumeTrailingBlankLine(content, statementEnd + 1),
  );
}

/// Trims a single declarator out of a statement that has other declarators
/// left over, by dropping one neighboring comma. Returns `null` if the
/// statement's shape can't be confidently resolved.
_Span? _partialDeclaratorSpan(
  UnusedDeclaration decl,
  String content,
  int Function(int line, int column) offsetOf,
) {
  final range = decl.range;
  final lineStart = offsetOf(range.startLine, 0);
  final baseStart = offsetOf(range.startLine, range.startColumn);
  final baseEnd = offsetOf(range.endLine, range.endColumn);

  final beforeText = content.substring(lineStart, baseStart);
  final leadingComma = _lastTopLevelComma(beforeText);
  final separator = _nextTopLevelSeparator(content, baseEnd);
  if (separator == null) {
    return null;
  }

  if (separator.$2 == ',') {
    final start = leadingComma == null
        ? baseStart
        : lineStart + leadingComma + 1;
    return (start: start, end: separator.$1 + 1);
  }
  if (leadingComma == null) {
    // Unreachable in practice: a sole declarator is always caught by
    // `_wholeStatementSpan` first. Handled anyway for robustness.
    return (start: lineStart, end: separator.$1 + 1);
  }
  // The last of several declarators: drop the now-orphaned leading comma,
  // but leave the `;` in place — it still terminates the statement.
  return (start: lineStart + leadingComma, end: baseEnd);
}

/// Extends [startLine] upward over contiguous doc-comment/annotation lines
/// (stopping at the first blank line), so a declaration's leading metadata is
/// removed along with it.
int _extendedTopLine(int startLine, List<String> lines) {
  var topLine = startLine;
  while (topLine - 1 >= 0) {
    final trimmed = lines[topLine - 1].trim();
    if (trimmed.isEmpty || !_looksLikeMetadata(trimmed)) {
      break;
    }
    topLine--;
  }
  return topLine;
}

bool _looksLikeMetadata(String trimmedLine) =>
    trimmedLine.startsWith('@') ||
    trimmedLine.startsWith('//') ||
    trimmedLine.startsWith('/*') ||
    trimmedLine.startsWith('*') ||
    trimmedLine.endsWith('*/');

/// Enum values are comma-separated, not self-terminating: dropping one
/// without also dropping a neighboring comma leaves invalid syntax. Prefers
/// consuming a trailing comma (keeps the shape for the common
/// trailing-comma style); falls back to the leading comma for the last value
/// in a list without one.
(int, int) _extendEnumValue(
  String content, {
  required int valueStart,
  required int baseStart,
  required int baseEnd,
}) {
  final forward = _nextNonWhitespace(content, baseEnd);
  if (forward != null && content[forward] == ',') {
    // Also swallow the blank left between this comma and the next value on
    // the same line, so a compact `enum E { a, b, c }` losing `b` reads
    // `enum E { a, c }` rather than `enum E { a,  c }`. Stop at a line break
    // to leave a multi-line enum's indentation intact.
    return (valueStart, _skipSameLineBlank(content, forward + 1));
  }
  final backward = _previousNonWhitespace(content, valueStart);
  if (backward != null && content[backward] == ',') {
    return (backward, baseEnd);
  }
  return (valueStart, baseEnd);
}

/// Extends past spaces and tabs starting at [from], but never across a line
/// break — used to consume the gap after a removed enum value's comma without
/// touching the next line's indentation.
int _skipSameLineBlank(String content, int from) {
  var i = from;
  while (i < content.length && (content[i] == ' ' || content[i] == '\t')) {
    i++;
  }
  return i;
}

/// Drops the separator comma left dangling when a compact single-line enum
/// loses a trailing run of values. Fires only when the merged removal [span]
/// is bracketed, on its own line, by a leading `,` and a trailing `}` with
/// nothing but spaces/tabs between — i.e. the removed values were the last in
/// the enum and a value still precedes them. In every other shape the comma
/// is a real separator that must stay, so the span is returned unchanged. The
/// same-line guards keep multi-line enums (whose preceding comma sits on an
/// earlier line) untouched.
_Span _absorbOrphanEnumComma(String content, _Span span) {
  var after = span.end;
  while (after < content.length &&
      (content[after] == ' ' || content[after] == '\t')) {
    after++;
  }
  if (after >= content.length || content[after] != '}') {
    return span;
  }
  var before = span.start - 1;
  while (before >= 0 && (content[before] == ' ' || content[before] == '\t')) {
    before--;
  }
  if (before < 0 || content[before] != ',') {
    return span;
  }
  return (start: before, end: span.end);
}

/// Walks forward from [from] through zero or more top-level `,` separators,
/// returning the index of the statement's terminating top-level `;`, or
/// `null` if one can't be found unambiguously.
int? _finalStatementEnd(String content, int from) {
  var pos = from;
  while (true) {
    final separator = _nextTopLevelSeparator(content, pos);
    if (separator == null) {
      return null;
    }
    if (separator.$2 == ';') {
      return separator.$1;
    }
    pos = separator.$1 + 1;
  }
}

/// The index of the last top-level (not nested in `()`, `[]`, `{}`, or `<>`)
/// comma in [text], or `null` if there isn't one.
int? _lastTopLevelComma(String text) {
  var depth = 0;
  int? last;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (ch == '(' || ch == '[' || ch == '{' || ch == '<') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}' || ch == '>') {
      if (depth > 0) {
        depth--;
      }
    } else if (depth == 0 && ch == ',') {
      last = i;
    }
  }
  return last;
}

/// Scans forward from [from] for the first top-level `,` or `;`, treating
/// `(`, `[`, and `{` as nesting (not `<>`: an initializer expression can
/// legitimately contain a `<` comparison). Returns its index and character,
/// or `null` if the scan runs off the end unbalanced or unresolved.
(int, String)? _nextTopLevelSeparator(String content, int from) {
  var depth = 0;
  for (var i = from; i < content.length; i++) {
    final ch = content[i];
    if (ch == '(' || ch == '[' || ch == '{') {
      depth++;
    } else if (ch == ')' || ch == ']' || ch == '}') {
      if (depth == 0) {
        return null;
      }
      depth--;
    } else if (depth == 0 && (ch == ',' || ch == ';')) {
      return (i, ch);
    }
  }
  return null;
}

/// If nothing but whitespace follows [end] on its line, extends it past the
/// line break — so deleting a declaration doesn't leave a blank line behind.
int _consumeTrailingBlankLine(String content, int end) {
  final nextNewline = content.indexOf('\n', end);
  final restOfLine = content.substring(
    end,
    nextNewline == -1 ? content.length : nextNewline,
  );
  if (restOfLine.trim().isNotEmpty) {
    return end;
  }
  return nextNewline == -1 ? content.length : nextNewline + 1;
}

int? _nextNonWhitespace(String content, int from) {
  for (var i = from; i < content.length; i++) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

int? _previousNonWhitespace(String content, int before) {
  for (var i = before - 1; i >= 0; i--) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

bool _isWhitespace(String ch) =>
    ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r';

List<_Span> _mergeSpans(List<_Span> spans) {
  final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
  final merged = <_Span>[];
  for (final span in sorted) {
    if (merged.isNotEmpty && span.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: span.end > last.end ? span.end : last.end,
      ));
    } else {
      merged.add(span);
    }
  }
  return merged;
}
