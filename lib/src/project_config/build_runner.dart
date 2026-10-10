import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/applied_builders.dart';
import 'package:ciach/src/project_config/build_extensions.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// The builder factories that the package's own build.yaml defines. build_runner
/// calls them, so nothing in the source references them.
Iterable<EntryPoint> buildRunnerEntryPoints(
  Pubspec pubspec,
  Map<Object?, Object?> buildYaml,
) => [
  if (pubspec.name case final name?)
    for (final section in const ['builders', 'post_process_builders'])
      if (buildYaml[section] case final Map<Object?, Object?> builders)
        for (final builder in builders.values) ..._factoriesOf(builder, name),
];

/// The factories of [builder], when its `import` points into [packageName].
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

/// The files written into the source tree by the builders applied to the
/// package. A builder's output can also be moved by a `build_extensions`
/// option in `targets:`, which source_gen 1.2 and freezed 1.0.1 accept.
Iterable<String> buildRunnerGeneratedGlobs(
  String rootPath,
  Pubspec pubspec,
  List<Map<Object?, Object?>> buildYamls,
) => [
  // Without a build.yaml, build_runner still applies auto-applied builders.
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
