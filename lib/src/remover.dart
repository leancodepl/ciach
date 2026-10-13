import 'dart:io';

import 'package:ciach/src/clause_entries.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/emptied_files.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.remover');

/// A `[start, end)` character-offset span within a file's content.
typedef _Span = ({int start, int end});

/// Deletes [declarations] from the files under [rootPath], rewriting each
/// affected file in a single pass.
///
/// Declarations whose range is fully contained within another declaration's
/// range (e.g. a method of a class that is itself unused) are removed once,
/// as part of removing the enclosing declaration. A field or top-level
/// variable is removed by deleting its [UnusedDeclaration.cut], which the
/// finder works out; one without a cut is left in place.
///
/// A rewritten file left with nothing but directives is then deleted, as are
/// the [emptyFiles]; see `deleteEmptiedFiles`. A class, mixin or extension
/// whose members are all removed stays in place and is listed in
/// [RemovalResult.emptiedContainers].
RemovalResult removeDeclarations(
  List<UnusedDeclaration> declarations,
  String rootPath, {
  List<String> emptyFiles = const [],
}) {
  final byFile = <String, List<UnusedDeclaration>>{};
  for (final decl in declarations) {
    // A blocked finding is reported but never auto-removed: deleting it safely
    // would need a source rewrite (e.g. an `if (x case DeadType())` branch), so
    // leave it — and anything coupled to it — entirely alone.
    if (decl.removalBlocked) {
      continue;
    }
    byFile.putIfAbsent(decl.filePath, () => []).add(decl);
    // Coupled removals are extra spans that must be deleted together with the
    // declaration to keep the source compiling (a dead StatefulWidget's paired
    // `State` subclass, or an override of a dead member), but that are not
    // findings in their own right. Each names its own file, so group it under
    // that file. Turn each into a synthetic declaration so it flows through
    // the normal removal pass and its span merges with the rest.
    for (final coupled in decl.coupledRemovals) {
      final range = coupled.range;
      byFile
          .putIfAbsent(coupled.filePath, () => [])
          .add(
            .new(
              name: '',
              kind: coupled.kind,
              filePath: coupled.filePath,
              line: range.startLine + 1,
              column: range.startColumn + 1,
              isPrivate: true,
              range: range,
              fullRange: coupled.fullRange,
              cut: coupled.cut,
            ),
          );
    }
  }

  final rewritten = <String>{};
  final emptied = <EmptiedContainer>[];
  RemovalException failure(FileSystemException e, String path) => .new(
    filePath: relativePosix(path, rootPath),
    cause: e.osError?.message ?? e.message,
    changedFiles: [for (final path in rewritten) relativePosix(path, rootPath)],
  );

  for (final entry in byFile.entries) {
    final path = absoluteUnder(entry.key, rootPath);
    final file = File(path);
    try {
      final content = file.readAsStringSync();
      final (updated, emptiedNames) = _removeFromContent(content, entry.value);
      emptied.addAll(
        emptiedNames.map((name) => (filePath: entry.key, name: name)),
      );
      if (updated != content) {
        file.writeAsStringSync(updated);
        rewritten.add(path);
        _log.fine(
          'Rewrote ${entry.key}: removed ${plural(entry.value.length, 'declaration', 'declarations')}.',
        );
      }
    } on FileSystemException catch (e) {
      throw failure(e, file.path);
    }
  }
  try {
    return .new(
      filesChanged: rewritten.length,
      deletedFiles: deleteEmptiedFiles({
        ...rewritten,
        for (final path in emptyFiles) absoluteUnder(path, rootPath),
      }, rootPath),
      emptiedContainers: emptied,
    );
  } on FileSystemException catch (e) {
    throw failure(e, e.path ?? rootPath);
  }
}

/// [removeDeclarations] failed on [filePath]; [changedFiles] were already
/// rewritten.
class RemovalException implements Exception {
  const RemovalException({
    required this.filePath,
    required this.cause,
    required this.changedFiles,
  });

  /// Root-relative `/`-path.
  final String filePath;

  final String cause;

  final List<String> changedFiles;

  String get message {
    final changed = changedFiles.isEmpty
        ? 'No file was changed.'
        : 'Already rewritten: ${changedFiles.join(', ')}.';
    return 'Could not remove declarations from $filePath: $cause. $changed';
  }

  @override
  String toString() => message;
}

/// Returns [content] with [decls] removed, and the names of the containers
/// this leaves with an empty body.
(String, Set<String>) _removeFromContent(
  String content,
  List<UnusedDeclaration> decls,
) {
  final lines = content.split('\n');
  final lineStarts = List<int>.filled(lines.length, 0);
  for (var i = 1; i < lines.length; i++) {
    lineStarts[i] = lineStarts[i - 1] + lines[i - 1].length + 1;
  }
  int offsetOf(int line, int column) => lineStarts[line] + column;

  final spans = [
    for (final decl in decls.whereNot((decl) => decl.isEnumValue))
      ?_spanOf(decl, content, lines, offsetOf),
  ];
  final enumSpans = [
    for (final decl in decls.where((decl) => decl.isEnumValue))
      ?_spanFor(decl, content, lines, offsetOf),
  ];
  // Merge each enum's value spans, then drop a separator comma left orphaned
  // when a trailing run of values is removed from a compact single-line enum.
  for (final span in _mergeSpans(enumSpans)) {
    spans.add(_absorbOrphanEnumComma(content, span));
  }

  if (spans.isEmpty) {
    return (content, const {});
  }

  final merged = _mergeSpans(spans);
  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in merged) {
    buffer.write(content.substring(cursor, span.start));
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  return (
    buffer.toString(),
    _emptiedContainers(content, merged, decls, offsetOf),
  );
}

/// Returns the containers of [decls] whose whole body the [merged] spans
/// remove.
///
/// A body counts as removed when the spans cover everything between its `{`
/// and `}` except whitespace and comments.
Set<String> _emptiedContainers(
  String content,
  List<_Span> merged,
  List<UnusedDeclaration> decls,
  int Function(int line, int column) offsetOf,
) {
  final members = [
    for (final decl in decls)
      if (decl.container case final container?)
        (
          container: container,
          start: offsetOf(decl.range.startLine, decl.range.startColumn),
        ),
  ];
  if (members.isEmpty) {
    return const {};
  }
  final code = stripComments(content);
  final runs = <_Span>[];
  for (final span in merged) {
    if (runs.lastOrNull case final last?
        when code.substring(last.end, span.start).trim().isEmpty) {
      runs.last = (start: last.start, end: span.end);
    } else {
      runs.add(span);
    }
  }
  return {
    for (final run in runs)
      if (previousNonWhitespace(code, run.start)?.let((i) => code[i]) == '{' &&
          nextNonWhitespace(code, run.end)?.let((i) => code[i]) == '}')
        for (final member in members)
          if (run.start <= member.start && member.start < run.end)
            member.container,
  };
}

/// Returns the span to delete for [decl], which isn't an enum value: the
/// [UnusedDeclaration.cut] of a field or variable, or [_spanFor] for anything
/// else. Returns `null` for a field or variable without a cut, which stays.
_Span? _spanOf(
  UnusedDeclaration decl,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  if (!declaratorKinds.contains(decl.kind)) {
    return _spanFor(decl, content, lines, offsetOf);
  }
  if (decl.cut case final cut?) {
    return _wholeLines(cut, content, lines, offsetOf);
  }
  _log.fine(
    'Left ${decl.qualifiedName} in ${decl.filePath} in place: the finder found no range to cut it out by.',
  );
  return null;
}

/// Computes the span to delete for an enum value or a "whole-node" kind
/// (class, function, method, property, …) whose [DeclarationRange] already
/// covers the full declaration. Deletion starts at `fullRange`.
_Span? _spanFor(
  UnusedDeclaration decl,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final range = decl.range;
  final baseStart = offsetOf(range.startLine, range.startColumn);
  final baseEnd = offsetOf(range.endLine, range.endColumn);
  if (decl.kind == clauseCutKind) {
    return (start: baseStart, end: baseEnd);
  }
  final fullStart = _startWithIndentation(decl.fullRange, lines, offsetOf);

  var start = fullStart;
  var end = baseEnd;

  if (decl.isEnumValue) {
    (start, end) = _extendEnumValue(
      content,
      valueStart: fullStart,
      baseStart: baseStart,
      baseEnd: baseEnd,
    );
  } else if (end < content.length && content[end] == ';') {
    // Some whole-node kinds (bodyless constructors, arrow-bodied members)
    // don't include their terminating `;` in the range.
    end++;
  }

  return (start: start, end: _consumeTrailingBlankLine(content, end));
}

/// Returns [cut] as a span. When only whitespace surrounds it on its first and
/// last lines, the span covers those whole lines, so a removed statement
/// leaves no empty line behind.
_Span _wholeLines(
  DeclarationRange cut,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final start = offsetOf(cut.startLine, cut.startColumn);
  final end = offsetOf(cut.endLine, cut.endColumn);
  final whole = _consumeTrailingBlankLine(content, end);
  return whole == end
      ? (start: start, end: end)
      : (start: _startWithIndentation(cut, lines, offsetOf), end: whole);
}

/// The start of [fullRange], moved to the start of its line when only
/// indentation precedes it.
int _startWithIndentation(
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
  final forward = nextNonWhitespace(content, baseEnd);
  if (forward != null && content[forward] == ',') {
    // Swallow the blank after the comma too, but stop at a line break so a
    // multi-line enum's indentation stays intact.
    return (valueStart, _skipSameLineBlank(content, forward + 1));
  }
  final backward = previousNonWhitespace(content, valueStart);
  if (backward != null && content[backward] == ',') {
    return (backward, baseEnd);
  }
  return (valueStart, baseEnd);
}

/// Skips spaces and tabs from [from], but never across a line break — used to
/// consume the gap after a removed enum value's comma.
int _skipSameLineBlank(String content, int from) {
  var i = from;
  while (i < content.length && _isSpaceOrTab(content[i])) {
    i++;
  }
  return i;
}

/// Whether [ch] is a space or tab — a blank that stays on the same line.
bool _isSpaceOrTab(String ch) => switch (ch) {
  ' ' || '\t' => true,
  _ => false,
};

/// Drops the separator comma left dangling when a compact single-line enum
/// loses a trailing run of values — when the merged [span] is bracketed on its
/// own line by a leading `,` and a trailing `}`. Otherwise the comma is a real
/// separator and the span is returned unchanged; the same-line guards leave
/// multi-line enums untouched.
_Span _absorbOrphanEnumComma(String content, _Span span) {
  var after = span.end;
  while (after < content.length && _isSpaceOrTab(content[after])) {
    after++;
  }
  if (after >= content.length || content[after] != '}') {
    return span;
  }
  var before = span.start - 1;
  while (before >= 0 && _isSpaceOrTab(content[before])) {
    before--;
  }
  if (before < 0 || content[before] != ',') {
    return span;
  }
  return (start: before, end: span.end);
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

List<_Span> _mergeSpans(List<_Span> spans) {
  final merged = <_Span>[];
  for (final span in spans.sortedBy<num>((s) => s.start)) {
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
