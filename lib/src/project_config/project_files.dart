import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/packages.dart';
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

/// Every package the nearest package_config.json resolves, by the directory
/// it lives in; a pub workspace keeps that file at its root.
Iterable<({String name, String root})> resolvedPackages(String rootPath) {
  final config = _nearestPackageConfig(rootPath);
  if (config == null) {
    return const [];
  }
  try {
    return switch (jsonDecode(config.readAsStringSync())) {
      {'packages': final List<Object?> packages} => [
        for (final package in packages)
          if (package case {
            'name': final String name,
            'rootUri': final String rootUri,
          })
            if (config.uri.resolve(rootUri) case final root
                when root.scheme == 'file')
              (name: name, root: root.toFilePath()),
      ],
      _ => const [],
    };
  } on FormatException catch (e) {
    _log.fine('Ignored ${config.path}, which does not parse: $e');
    return const [];
  }
}

File? _nearestPackageConfig(String rootPath) {
  for (var dir = rootPath; ; dir = p.dirname(dir)) {
    final config = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (config.existsSync()) {
      return config;
    }
    if (p.dirname(dir) == dir) {
      return null;
    }
  }
}

String escapeGlob(String literal) =>
    literal.replaceAllMapped(RegExp(r'[*?\[\]{},\\]'), (m) => '\\${m[0]}');

/// POSIX directories, relative to [rootPath], of the packages in it: `''` for
/// [rootPath] itself, then each nested one with a pubspec.yaml.
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
