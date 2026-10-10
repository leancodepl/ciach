import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/applied_builders.dart';
import 'package:ciach/src/project_config/build_extensions.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Builder factories the package's own build.yaml defines.
Iterable<EntryPoint> buildRunnerEntryPoints(
  Pubspec pubspec,
  Map<Object?, Object?>? buildYaml,
) => [
  if (pubspec.name case final name?)
    for (final section in const ['builders', 'post_process_builders'])
      if (buildYaml?[section] case final Map<Object?, Object?> builders)
        for (final builder in builders.values) ..._factoriesOf(builder, name),
];

/// The factories of [builder] when it is imported from [packageName].
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
      yield* configRule(factory, [file], 'a builder factory in build.yaml');
    }
  }
}

/// Source output of the builders applied to the package, and of
/// `build_extensions` given as a builder option, which source_gen and freezed
/// accept.
Iterable<String> buildRunnerGeneratedGlobs(
  String rootPath,
  Pubspec pubspec,
  Map<Object?, Object?>? buildYaml,
) => [
  for (final definition in appliedBuilders(rootPath, pubspec, buildYaml))
    if (definition case {
      'build_to': 'source',
      'build_extensions': final Map<Object?, Object?> extensions,
    })
      ...outputGlobs(extensions),
  for (final (key: _, :config) in targetBuilders(targetsOf(buildYaml)))
    if (config case {
      'options': {'build_extensions': final Map<Object?, Object?> extensions},
    })
      ...outputGlobs(extensions),
];
