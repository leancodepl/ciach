import 'package:ciach/src/packages.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// Returns the definitions of the builders that build_runner applies to the
/// package at [rootPath]. A builder can be applied in three ways:
/// - by its `auto_apply` setting, where `dependents` counts only for a direct
///   dependency;
/// - by the `targets:` of the package;
/// - by the `applies_builders` list of another builder that is applied.
///
/// This follows build_config 0.4.2.
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

/// The package that defines a builder, and the definition of the builder.
typedef _Definition = ({String package, Map<Object?, Object?> definition});

/// Returns the builders that are defined by the root package and by every
/// package in its package config. The keys have the form `package:name`.
Map<String, _Definition> _definitions(
  String rootPath,
  String? rootName,
  Map<Object?, Object?>? rootBuildYaml,
) => {
  if (rootName != null) ..._definedIn(rootName, rootBuildYaml),
  // In a pub workspace, package_config.json is in the root of the workspace.
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

/// Returns [autoApplied], changed by the targets in [buildYaml]. When a target
/// configures a builder, the builder is enabled, unless the configuration says
/// `enabled: false`. When every target sets `auto_apply_builders: false`, the
/// builders that are only auto-applied are dropped.
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

/// Returns [applied], together with every builder that they list under
/// `applies_builders`. The builders that are added this way can list more
/// builders, which are added as well.
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

/// Returns the builder key [key] in the form `pkg:name`. build_runner also
/// accepts `pkg|name`, `:name` for a builder of the root package, and `name`
/// as a short form of `name:name`.
String _builderKey(String key, String? rootName) =>
    switch (key.replaceFirst('|', ':')) {
      final local when local.startsWith(':') => '$rootName$local',
      final qualified when qualified.contains(':') => qualified,
      final bare => '$bare:$bare',
    };
