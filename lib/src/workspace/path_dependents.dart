import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
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
  if (repository == null || dirContains(analysisRoot, repository)) {
    return const [];
  }
  return [
    for (final libDir in scanPackageTree(repository).libDirs.sorted())
      if (p.dirname(libDir) case final dir
          when !dirContains(analysisRoot, dir) && _dependsByPath(dir, rootPath))
        dir,
  ];
}

/// The nearest directory at or above [dir] with a `.git`.
String? _repositoryOf(String dir) =>
    dirAndAncestors(dir).firstWhereOrNull(isRepositoryRoot);

/// Whether the pubspec in [dir] depends on the package at [target] by
/// `path:`.
bool _dependsByPath(String dir, String target) {
  final pubspec = readPubspec(dir).yaml;
  return [
    for (final section in const [
      'dependencies',
      'dev_dependencies',
      'dependency_overrides',
    ])
      if (pubspec?[section] case final Map<Object?, Object?> deps)
        ...deps.values,
  ].any(
    (dep) => switch (dep) {
      {'path': final String path} => p.equals(
        p.normalize(p.join(dir, path)),
        target,
      ),
      _ => false,
    },
  );
}
