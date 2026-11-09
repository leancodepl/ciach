import 'dart:io';

import 'package:ciach/src/project_config/project_files.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Returns the package's `build.yaml`, and every `build.<name>.yaml` that
/// `build_runner --config <name>` can use instead of it.
List<Map<Object?, Object?>> readBuildYamls(String rootPath) => [
  for (final path in [
    for (final entity in Directory(rootPath).listSync(followLinks: false))
      if (entity case File(
        :final path,
      ) when _buildYamlName.hasMatch(p.basename(path)))
        path,
  ].sorted())
    ?readYamlMap(path),
];

final _buildYamlName = RegExp(r'^build(\.[^.]+)?\.yaml$');

/// Returns the configurations of the targets that are listed under `targets:`
/// in [buildYaml].
Iterable<Map<Object?, Object?>> targetsOf(Map<Object?, Object?>? buildYaml) =>
    switch (buildYaml?['targets']) {
      final Map<Object?, Object?> targets =>
        targets.values.whereType<Map<Object?, Object?>>(),
      _ => const [],
    };

/// Returns every builder that [targets] configure. Each builder comes with its
/// key, exactly as it is written, and with its configuration.
Iterable<({String key, Object? config})> targetBuilders(
  Iterable<Map<Object?, Object?>> targets,
) => [
  for (final target in targets)
    if (target case {'builders': final Map<Object?, Object?> builders})
      for (final MapEntry(key: name, value: config) in builders.entries)
        if (name case final String key) (key: key, config: config),
];
