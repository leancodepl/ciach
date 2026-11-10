import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final _log = Logger('ciach.finder');

/// The parts of `pubspec.yaml` that are used by the project config.
typedef Pubspec = ({
  String? name,
  Set<String> dependencies,
  Map<Object?, Object?>? yaml,
});

Pubspec readPubspec(String rootPath) {
  final yaml = readYamlMap(p.join(rootPath, 'pubspec.yaml'));
  return (
    name: switch (yaml?['name']) {
      final String name => name,
      _ => null,
    },
    dependencies: {
      for (final section in const ['dependencies', 'dev_dependencies'])
        if (yaml?[section] case final Map<Object?, Object?> deps)
          ...deps.keys.whereType<String>(),
    },
    yaml: yaml,
  );
}

Map<Object?, Object?>? readYamlMap(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return null;
  }
  try {
    return switch (loadYaml(file.readAsStringSync(), sourceUrl: file.uri)) {
      final Map<Object?, Object?> map => map,
      _ => null,
    };
  } on Exception catch (e) {
    _log.fine('Ignored $path, which does not parse: $e');
    return null;
  }
}

Iterable<EntryPoint> configRule(
  String name,
  List<String> files,
  String reason,
) sync* {
  try {
    yield EntryPoint.fromConfig(name, files: files, reason: reason);
  } on FormatException catch (e) {
    _log.fine('Ignored the entry point $name in ${files.join(', ')}: $e');
  }
}

String escapeGlob(String literal) =>
    literal.replaceAllMapped(RegExp(r'[*?\[\]{},\\]'), (m) => '\\${m[0]}');

/// Returns the directories of the packages in [tree], which was scanned from
/// [rootPath], as POSIX paths that are relative to [rootPath]. The first one
/// is `''`, which stands for [rootPath] itself. It is followed by every nested
/// directory that has a pubspec.yaml, sorted.
List<String> packageDirs(String rootPath, PackageTree tree) {
  final nested = {
    for (final libDir in tree.libDirs)
      relativePosix(p.dirname(libDir), rootPath),
  }..remove('.');
  return ['', ...nested.toList()..sort()];
}

/// Returns the Dart files of [tree], which was scanned from [rootPath], by
/// the directory in [dirs] of the package that each file belongs to. A file
/// in a nested package belongs to the nested package only.
Map<String, List<String>> dartFilesByPackage(
  String rootPath,
  List<String> dirs,
  PackageTree tree,
) => groupBy(
  tree.dartFiles,
  // [dirs] are sorted, so the last one that contains a file is the innermost.
  (file) =>
      dirs.lastWhere((dir) => p.isWithin(p.absolute(rootPath, dir), file)),
);
