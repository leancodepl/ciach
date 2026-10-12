import 'dart:io';

import 'package:ciach/src/emptied_files.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/removal_spans.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.remover');

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
/// A rewritten file left with nothing but directives is then deleted; see
/// `deleteEmptiedFiles`.
RemovalResult removeDeclarations(
  List<UnusedDeclaration> declarations,
  String rootPath,
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
    // Coupled removals are extra whole-node spans that must be deleted together
    // with the declaration to keep the source compiling (a dead StatefulWidget's
    // paired `State` subclass, or a dead sealed member's `case` arm), but that
    // are not findings in their own right. Each names its own file — usually the
    // declaration's, but a `case` arm can live elsewhere — so group it under
    // that file. Turn each into a synthetic whole-node declaration so it flows
    // through the normal removal pass and its span merges with the rest.
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
    final file = File(p.joinAll([rootPath, ...p.posix.split(entry.key)]));
    try {
      final content = file.readAsStringSync();
      final updated = removeFromContent(content, entry.value);
      if (updated != content) {
        file.writeAsStringSync(updated);
        rewritten.add(p.normalize(file.absolute.path));
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
      deletedFiles: deleteEmptiedFiles(rewritten, rootPath),
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
