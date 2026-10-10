import 'dart:io';

import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// `build.yaml` and every `build.<name>.yaml` build_runner can pick with
/// `--config`.
List<Map<Object?, Object?>> readBuildYamls(String rootPath) => [
  for (final file in _buildYamlFiles(rootPath)) ?readYamlMap(file),
];

final _buildYamlName = RegExp(r'^build(\.[^.]+)?\.yaml$');

Iterable<String> _buildYamlFiles(String rootPath) {
  final dir = Directory(rootPath);
  if (!dir.existsSync()) {
    return const [];
  }
  return [
    for (final entity in dir.listSync(followLinks: false))
      if (entity is File && _buildYamlName.hasMatch(p.basename(entity.path)))
        entity.path,
  ]..sort();
}

/// The maps under `targets:` in [buildYaml].
Iterable<Map<Object?, Object?>> targetsOf(Map<Object?, Object?>? buildYaml) =>
    switch (buildYaml?['targets']) {
      final Map<Object?, Object?> targets =>
        targets.values.whereType<Map<Object?, Object?>>(),
      _ => const [],
    };

/// Each builder [targets] configure, by its key as written.
Iterable<({String key, Object? config})> targetBuilders(
  Iterable<Map<Object?, Object?>> targets,
) => [
  for (final target in targets)
    if (target case {'builders': final Map<Object?, Object?> builders})
      for (final MapEntry(:key, value: config) in builders.entries)
        if (key is String) (key: key, config: config),
];
