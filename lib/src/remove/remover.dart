import 'dart:io';

import 'package:ciach/src/model/removal_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/remove/declaration_spans.dart';
import 'package:ciach/src/remove/emptied_files.dart';
import 'package:ciach/src/remove/text_spans.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.remover');

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
/// the [emptyFiles]; see `deleteEmptiedFiles`.
RemovalResult removeDeclarations(
  List<UnusedDeclaration> declarations,
  String rootPath, {
  List<String> emptyFiles = const [],
}) {
  final byFile = _byFile(declarations);
  final rewritten = <String>{};
  // For each file, where the comments kept above removed code start, counted
  // from the end of the file. Deleting emptied files later drops imports near
  // the top of other files, which shifts every offset counted from the start
  // but none counted from the end.
  final keptComments = <String, List<int>>{};
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
      final (:updated, :commentsFromEnd) = _removeFromContent(
        content,
        entry.value,
      );
      if (updated != content) {
        file.writeAsStringSync(updated);
        rewritten.add(path);
        _log.fine(
          'Rewrote ${entry.key}: removed ${plural(entry.value.length, 'declaration', 'declarations')}.',
        );
        if (commentsFromEnd.isNotEmpty) {
          keptComments[entry.key] = commentsFromEnd;
        }
      }
    } on FileSystemException catch (e) {
      throw failure(e, file.path);
    }
  }
  try {
    final deletedFiles = deleteEmptiedFiles({
      ...rewritten,
      for (final path in emptyFiles) absoluteUnder(path, rootPath),
    }, rootPath);
    return .new(
      filesChanged: rewritten.length,
      deletedFiles: deletedFiles,
      leftComments: _leftComments(keptComments, rootPath),
    );
  } on FileSystemException catch (e) {
    throw failure(e, e.path ?? rootPath);
  }
}

/// The declarations to remove, and their coupled removals, by file.
Map<String, List<UnusedDeclaration>> _byFile(
  List<UnusedDeclaration> declarations,
) {
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
  return byFile;
}

/// The line of each comment in [keptComments], read from the files as they are
/// once every change is written. A comment in a file that was deleted is left
/// out.
List<LeftComment> _leftComments(
  Map<String, List<int>> keptComments,
  String rootPath,
) {
  final left = <LeftComment>[];
  for (final filePath in keptComments.keys.sorted()) {
    final file = File(absoluteUnder(filePath, rootPath));
    if (!file.existsSync()) {
      continue;
    }
    final content = file.readAsStringSync();
    final starts = lineStartsOf(content);
    for (final fromEnd in keptComments[filePath]!) {
      left.add((
        filePath: filePath,
        line: lowerBound(starts, content.length - fromEnd + 1),
      ));
    }
  }
  return left;
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

/// Returns [content] with [decls] removed, and how far from the end of the
/// result each `//` comment block kept directly above removed code starts.
({String updated, List<int> commentsFromEnd}) _removeFromContent(
  String content,
  List<UnusedDeclaration> decls,
) {
  final lines = content.split('\n');
  final comments = _OwnLineComments(content);
  int offsetOf(int line, int column) => comments.starts[line] + column;

  final spans = [
    for (final decl in decls.whereNot((decl) => decl.isEnumValue))
      ?_spanOf(decl, content, lines, offsetOf),
  ];
  final enumSpans = [
    for (final decl in decls.where((decl) => decl.isEnumValue))
      ?spanFor(decl, content, lines, offsetOf),
  ];
  // Merge each enum's value spans, then drop a separator comma left orphaned
  // when a trailing run of values is removed from a compact single-line enum.
  for (final span in mergeSpans(enumSpans)) {
    spans.add(absorbOrphanEnumComma(content, span));
  }

  if (spans.isEmpty) {
    return (updated: content, commentsFromEnd: const []);
  }

  final kept = <int>[];
  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in mergeSpans([
    for (final span in spans) comments.withNextLineDirectivesAbove(span),
  ])) {
    buffer.write(content.substring(cursor, span.start));
    if (comments.blockAbove(span.start, after: cursor) case final block?) {
      kept.add(buffer.length - (span.start - block));
    }
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  final updated = buffer.toString();
  return (
    updated: updated,
    commentsFromEnd: [for (final offset in kept) updated.length - offset],
  );
}

/// The lines of a file that hold nothing but a `//` comment.
final class _OwnLineComments {
  _OwnLineComments(this._content) : starts = lineStartsOf(_content);

  final String _content;

  /// The offset at which each line starts.
  final List<int> starts;

  /// The `//` comments by offset, read only once a line starts with `//`.
  late final _byOffset = {
    for (final comment in lineComments(_content)) comment.offset: comment,
  };

  /// [span], with the lines directly above it that apply to the next line
  /// only, such as `// ignore:`, which would otherwise apply to whatever
  /// follows.
  Span withNextLineDirectivesAbove(Span span) {
    final first = _lineStartingAt(span.start);
    if (first == null) {
      return span;
    }
    var line = first;
    while (line > 0 &&
        (_commentOn(line - 1)?.text.let(isNextLineDirective) ?? false)) {
      line--;
    }
    return (start: starts[line], end: span.end);
  }

  /// The start of the `//` comment block directly above [offset], with no
  /// blank line between and none of it before [after]: its topmost plain
  /// comment. Doc comments and tool directives, such as `// ciach:` markers
  /// and `// ignore:` comments, aren't plain.
  int? blockAbove(int offset, {required int after}) {
    int? block;
    var line = _lineStartingAt(offset);
    while (line != null && line > 0 && starts[line - 1] >= after) {
      line--;
      final comment = _commentOn(line);
      if (comment == null || comment.text.startsWith('///')) {
        break;
      }
      if (!isToolDirective(comment.text) &&
          !isNextLineDirective(comment.text)) {
        block = comment.offset;
      }
    }
    return block;
  }

  /// The line that starts at [offset], if one does.
  int? _lineStartingAt(int offset) {
    final line = lowerBound(starts, offset);
    return line < starts.length && starts[line] == offset ? line : null;
  }

  /// The `//` comment that is all of [line] but its indentation, if any.
  ({int offset, String text})? _commentOn(int line) {
    final start = nextNonWhitespace(_content, starts[line]);
    final end = line + 1 < starts.length ? starts[line + 1] : _content.length;
    if (start == null || start >= end || !_content.startsWith('//', start)) {
      return null;
    }
    return _byOffset[start];
  }
}

/// Returns the span to delete for [decl], which isn't an enum value: its
/// [UnusedDeclaration.cut] if it has one, else [spanFor]. Returns `null` for
/// a field or variable without a cut, which stays.
Span? _spanOf(
  UnusedDeclaration decl,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  if (decl.cut case final cut?) {
    return _wholeLines(cut, content, lines, offsetOf);
  }
  if (!declaratorKinds.contains(decl.kind)) {
    return spanFor(decl, content, lines, offsetOf);
  }
  _log.fine(
    'Left ${decl.qualifiedName} in ${decl.filePath} in place: the finder found no range to cut it out by.',
  );
  return null;
}

/// Returns [cut] as a span. When only whitespace surrounds it on its first and
/// last lines, the span covers those whole lines, so a removed statement
/// leaves no empty line behind.
Span _wholeLines(
  DeclarationRange cut,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final start = offsetOf(cut.startLine, cut.startColumn);
  final end = offsetOf(cut.endLine, cut.endColumn);
  final whole = consumeLineEnd(content, end);
  return whole == end
      ? (start: start, end: end)
      : (start: startWithIndentation(cut, lines, offsetOf), end: whole);
}
