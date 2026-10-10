import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/packages.dart';
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

/// Returns the directories of the packages in [rootPath], as POSIX paths that
/// are relative to [rootPath]. The first one is `''`, which stands for
/// [rootPath] itself. It is followed by every nested directory that has a
/// pubspec.yaml.
Iterable<String> packageDirs(String rootPath) {
  if (!Directory(rootPath).existsSync()) {
    return const [];
  }
  final nested = {
    for (final libDir in scanPackageTree(rootPath).libDirs)
      p.split(p.relative(p.dirname(libDir), from: rootPath)).join('/'),
  }..remove('.');
  return ['', ...nested.toList()..sort()];
}
