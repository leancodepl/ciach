import 'package:ciach/src/packages.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The definitions of the builders that build_runner applies to the package at
/// [rootPath]. A builder is applied by its `auto_apply` setting (`dependents`
/// only counts for a direct dependency), by the package's `targets:`, or by
/// another applied builder's `applies_builders`. This follows build_config up
/// to 0.4.2, the version that added `auto_apply_builders`.
Iterable<Map<Object?, Object?>> appliedBuilders(
  String rootPath,
  Pubspec pubspec,
  Map<Object?, Object?>? rootBuildYaml,
) {
  final definitions = _definitions(rootPath, pubspec.name, rootBuildYaml);
  final applied = _byTargets(
    _autoApplied(definitions, pubspec),
    rootBuildYaml,
    pubspec.name,
  );
  return [
    for (final key in _withAppliedBuilders(applied, definitions, pubspec.name))
      ?definitions[key]?.definition,
  ];
}

/// The package that defines a builder, and the builder's definition.
typedef _Definition = ({String package, Map<Object?, Object?> definition});

/// The builders defined by the root package and by every package in its
/// package config, keyed by `package:name`.
Map<String, _Definition> _definitions(
  String rootPath,
  String? rootName,
  Map<Object?, Object?>? rootBuildYaml,
) => {
  if (rootName != null) ..._definedIn(rootName, rootBuildYaml),
  // A pub workspace keeps package_config.json at its root.
  for (final Package(:name, :root)
      in PackageResolver().configOf(rootPath)?.packages ?? const <Package>[])
    if (name != rootName && root.isScheme('file'))
      ..._definedIn(name, readYamlMap(p.join(root.toFilePath(), 'build.yaml'))),
};

Map<String, _Definition> _definedIn(
  String package,
  Map<Object?, Object?>? buildYaml,
) => switch (buildYaml?['builders']) {
  final Map<Object?, Object?> builders => {
    for (final MapEntry(:key, value: definition) in builders.entries)
      if ((key, definition) case (
        final String name,
        final Map<Object?, Object?> definition,
      ))
        '$package:$name': (package: package, definition: definition),
  },
  _ => const {},
};

Set<String> _autoApplied(
  Map<String, _Definition> definitions,
  Pubspec pubspec,
) => {
  for (final MapEntry(:key, value: (:package, :definition))
      in definitions.entries)
    if (switch (definition['auto_apply']) {
      'all_packages' => true,
      'dependents' => pubspec.dependencies.contains(package),
      'root_package' => package == pubspec.name,
      _ => false,
    })
      key,
};

/// [autoApplied], changed by the targets in [buildYaml]. Configuring a builder
/// in a target enables it (since build_config 0.2.1), unless the
/// configuration says `enabled: false`. When every target sets
/// `auto_apply_builders: false` (since 0.4.2), the builders that are only
/// auto-applied are dropped.
Set<String> _byTargets(
  Set<String> autoApplied,
  Map<Object?, Object?>? buildYaml,
  String? rootName,
) {
  final targets = targetsOf(buildYaml).toList();
  final optedOut =
      targets.isNotEmpty &&
      targets.every((target) => target['auto_apply_builders'] == false);
  final applied = optedOut ? <String>{} : {...autoApplied};
  for (final (:key, :config) in targetBuilders(targets)) {
    if (config case {'enabled': false}) {
      applied.remove(_builderKey(key, rootName));
    } else {
      applied.add(_builderKey(key, rootName));
    }
  }
  return applied;
}

/// [applied], plus every builder they list under `applies_builders`, and so
/// on transitively.
Set<String> _withAppliedBuilders(
  Set<String> applied,
  Map<String, _Definition> definitions,
  String? rootName,
) {
  final all = {...applied};
  final pending = [...applied];
  while (pending.isNotEmpty) {
    if (definitions[pending.removeLast()]?.definition['applies_builders']
        case final List<Object?> more) {
      pending.addAll([
        for (final key in more.whereType<String>())
          if (all.add(_builderKey(key, rootName))) _builderKey(key, rootName),
      ]);
    }
  }
  return all;
}

/// Normalizes a builder key to `pkg:name`. build_runner also accepts
/// `pkg|name`, `:name` for a builder of the root package, and `name` for
/// `name:name`.
String _builderKey(String key, String? rootName) =>
    switch (key.replaceFirst('|', ':')) {
      final local when local.startsWith(':') => '$rootName$local',
      final qualified when qualified.contains(':') => qualified,
      final bare => '$bare:$bare',
    };
