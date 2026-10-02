import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final _log = Logger('ciach.finder');

/// `pubspec.yaml`, as the project config reads it.
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

/// From the nearest package_config.json; a pub workspace keeps it at its
/// root.
Iterable<({String name, String root})> resolvedPackages(String rootPath) sync* {
  for (var dir = rootPath; ; dir = p.dirname(dir)) {
    final config = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      try {
        if (jsonDecode(config.readAsStringSync()) case {
          'packages': final List<Object?> packages,
        }) {
          for (final package in packages) {
            if (package case {
              'name': final String name,
              'rootUri': final String rootUri,
            }) {
              final root = config.uri.resolve(rootUri);
              if (root.scheme == 'file') {
                yield (name: name, root: root.toFilePath());
              }
            }
          }
        }
      } on FormatException catch (e) {
        _log.fine('Ignored ${config.path}, which does not parse: $e');
      }
      return;
    }
    if (p.dirname(dir) == dir) {
      return;
    }
  }
}

String escapeGlob(String literal) =>
    literal.replaceAllMapped(RegExp(r'[*?\[\]{},\\]'), (m) => '\\${m[0]}');

/// POSIX directories, relative to [rootPath], of the packages in it: `''` for
/// [rootPath] itself, then each nested one with a pubspec.yaml.
Iterable<String> packageDirs(String rootPath) sync* {
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return;
  }
  yield '';
  final nested = [
    for (final entity in root.listSync(recursive: true, followLinks: false))
      if (entity is File && p.basename(entity.path) == 'pubspec.yaml')
        p.split(p.relative(p.dirname(entity.path), from: rootPath)).join('/'),
  ]..sort();
  for (final dir in nested) {
    if (dir != '.' && !isInSkippedDir(dir)) {
      yield dir;
    }
  }
}
