/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:path/path.dart' as p;

extension AbsolutePath on String {
  /// This path made absolute and normalized.
  String get absoluteNormalized => p.normalize(p.absolute(this));
}

/// [absPath] expressed relative to [rootPath], with `/` separators — the form
/// used for a finding's and a coupled removal's `filePath`.
String relativePosix(String absPath, String rootPath) =>
    p.split(p.relative(absPath, from: rootPath)).join('/');

/// The absolute, normalized path of [posixPath], a root-relative `/`-path such
/// as a finding's `filePath`, under [rootPath]. The inverse of [relativePosix].
String absoluteUnder(String posixPath, String rootPath) =>
    p.joinAll([rootPath, ...p.posix.split(posixPath)]).absoluteNormalized;

/// A usage site's path for display: relative to [rootPath] inside the scanned
/// package, to [analysisRoot] outside it — `pkgs/app/lib/x.dart`, not
/// `../app/lib/x.dart`.
String relativeUsagePosix(
  String absPath,
  String rootPath,
  String analysisRoot,
) => p.isWithin(rootPath, absPath)
    ? relativePosix(absPath, rootPath)
    : relativePosix(absPath, analysisRoot);

/// Whether [dir] is [path] or a directory above it.
bool dirContains(String dir, String path) =>
    p.equals(dir, path) || p.isWithin(dir, path);

/// [dir] and each directory above it, nearest first: `/a/b`, `/a` and `/`
/// for `/a/b`.
Iterable<String> dirAndAncestors(String dir) sync* {
  for (var current = dir; ; current = p.dirname(current)) {
    yield current;
    if (p.dirname(current) == current) {
      return;
    }
  }
}

/// Whether [dir] holds a `.git`: a directory in a plain clone, a file in a
/// submodule or a worktree.
bool isRepositoryRoot(String dir) =>
    FileSystemEntity.typeSync(p.join(dir, '.git')) != .notFound;
