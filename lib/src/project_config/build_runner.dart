import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/applied_builders.dart';
import 'package:ciach/src/project_config/build_extensions.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the builder factories that are defined in the package's own
/// build.yaml. build_runner calls these factories, so nothing in the source
/// code references them.
Iterable<EntryPoint> buildRunnerEntryPoints(
  Pubspec pubspec,
  Map<Object?, Object?> buildYaml,
) => [
  if (pubspec.name case final name?)
    for (final section in const ['builders', 'post_process_builders'])
      if (buildYaml[section] case final Map<Object?, Object?> builders)
        for (final builder in builders.values) ..._factoriesOf(builder, name),
];

/// Returns the factories of [builder] when its `import` points to a file in
/// [packageName].
Iterable<EntryPoint> _factoriesOf(Object? builder, String packageName) sync* {
  if (builder case {
    'import': final String import,
  } when import.startsWith('package:$packageName/')) {
    final file = 'lib/${import.substring('package:$packageName/'.length)}';
    final factories = switch (builder) {
      {'builder_factories': final List<Object?> names} => names,
      {'builder_factory': final String name} => [name],
      _ => const <Object?>[],
    };
    for (final factory in factories.whereType<String>()) {
      yield* configRule(factory, [file], 'called by build_runner');
    }
  }
}

/// Returns globs for the files that the applied builders write into the
/// source tree of the package. A `build_extensions` option in `targets:` can
/// move the output of a builder to another place. source_gen 1.2 and freezed
/// 1.0.1 support this option.
Iterable<String> buildRunnerGeneratedGlobs(
  String rootPath,
  Pubspec pubspec,
  List<Map<Object?, Object?>> buildYamls,
) => [
  // A package without a build.yaml still gets the builders that are applied
  // automatically.
  for (final buildYaml in buildYamls.isEmpty ? const [null] : buildYamls)
    for (final definition in appliedBuilders(rootPath, pubspec, buildYaml))
      if (definition case {
        'build_to': 'source',
        'build_extensions': final Map<Object?, Object?> extensions,
      })
        ...outputGlobs(extensions),
  for (final (key: _, :config) in targetBuilders(buildYamls.expand(targetsOf)))
    if (config case {
      'options': {'build_extensions': final Map<Object?, Object?> extensions},
    })
      ...outputGlobs(extensions),
];
