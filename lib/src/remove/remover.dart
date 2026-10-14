import 'dart:io';

import 'package:ciach/src/model/removal_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/remove/declaration_spans.dart';
import 'package:ciach/src/remove/emptied_files.dart';
import 'package:ciach/src/remove/text_spans.dart';
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
      final updated = _removeFromContent(content, entry.value);
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

/// Returns [content] with [decls] removed.
String _removeFromContent(String content, List<UnusedDeclaration> decls) {
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
      ?spanFor(decl, content, lines, offsetOf),
  ];
  // Merge each enum's value spans, then drop a separator comma left orphaned
  // when a trailing run of values is removed from a compact single-line enum.
  for (final span in mergeSpans(enumSpans)) {
    spans.add(absorbOrphanEnumComma(content, span));
  }

  if (spans.isEmpty) {
    return content;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in mergeSpans(spans)) {
    buffer.write(content.substring(cursor, span.start));
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  return buffer.toString();
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
  final whole = consumeTrailingBlankLine(content, end);
  return whole == end
      ? (start: start, end: end)
      : (start: startWithIndentation(cut, lines, offsetOf), end: whole);
}
