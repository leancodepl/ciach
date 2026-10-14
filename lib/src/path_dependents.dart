import 'dart:io';

import 'package:ciach/src/packages.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// The packages in the git repository holding [rootPath], outside the
/// [analysisRoot], that depend on the package at [rootPath] by `path:`: their
/// uses of it are invisible to the run. Both paths are absolute and
/// normalized. Empty for a member of a pub workspace, whose analysis covers
/// the workspace, and outside a git repository.
List<String> pathDependentsOutside(String rootPath, String analysisRoot) {
  if (readPubspec(rootPath).yaml case null || {'resolution': 'workspace'}) {
    return const [];
  }
  final repository = _repositoryOf(rootPath);
  if (repository == null ||
      p.equals(analysisRoot, repository) ||
      p.isWithin(analysisRoot, repository)) {
    return const [];
  }
  return [
    for (final libDir in scanPackageTree(repository).libDirs.toList()..sort())
      if (p.dirname(libDir) case final dir
          when !p.equals(dir, analysisRoot) &&
              !p.isWithin(analysisRoot, dir) &&
              _dependsByPath(dir, rootPath))
        dir,
  ];
}

/// The nearest directory that is or contains each of [dirs], absolute and
/// normalized.
String commonAncestor(List<String> dirs) {
  var common = dirs.first;
  for (final dir in dirs.skip(1)) {
    while (!p.equals(common, dir) && !p.isWithin(common, dir)) {
      common = p.dirname(common);
    }
  }
  return common;
}

/// The nearest directory at or above [dir] with a `.git`.
String? _repositoryOf(String dir) {
  for (var current = dir; ; current = p.dirname(current)) {
    if (FileSystemEntity.typeSync(p.join(current, '.git')) != .notFound) {
      return current;
    }
    if (p.dirname(current) == current) {
      return null;
    }
  }
}

/// Whether the pubspec in [dir] depends on the package at [target] by
/// `path:`.
bool _dependsByPath(String dir, String target) {
  final pubspec = readPubspec(dir).yaml;
  for (final section in const [
    'dependencies',
    'dev_dependencies',
    'dependency_overrides',
  ]) {
    if (pubspec?[section] case final Map<Object?, Object?> deps) {
      for (final dep in deps.values) {
        if (dep case {
          'path': final String path,
        } when p.equals(p.normalize(p.join(dir, path)), target)) {
          return true;
        }
      }
    }
  }
  return false;
}
