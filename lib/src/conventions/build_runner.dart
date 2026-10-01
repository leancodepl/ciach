import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/project_files.dart';
import 'package:path/path.dart' as p;

Map<Object?, Object?>? readBuildYaml(String rootPath) =>
    readYamlMap(p.join(rootPath, 'build.yaml'));

/// Builder factories the package's own build.yaml defines.
Iterable<EntryPoint> buildRunnerEntryPoints(
  Pubspec pubspec,
  Map<Object?, Object?>? buildYaml,
) => switch (pubspec.name) {
  final name? => _builderFactories(buildYaml, name),
  null => const [],
};

/// Source output of the builders applied to the package.
Iterable<String> buildRunnerGeneratedGlobs(
  String rootPath,
  Pubspec pubspec,
  Map<Object?, Object?>? buildYaml,
) sync* {
  for (final builder in _appliedBuilders(rootPath, pubspec.name, buildYaml)) {
    if (builder.definition case {
      'build_to': 'source',
      'build_extensions': final Map<Object?, Object?> extensions,
    }) {
      yield* outputGlobs(extensions);
    }
  }
  yield* _buildExtensionOptions(buildYaml);
}

Iterable<EntryPoint> _builderFactories(
  Map<Object?, Object?>? buildYaml,
  String packageName,
) sync* {
  for (final section in const ['builders', 'post_process_builders']) {
    if (buildYaml?[section] case final Map<Object?, Object?> builders) {
      for (final builder in builders.values) {
        if (builder case {
          'import': final String import,
        } when import.startsWith('package:$packageName/')) {
          final file =
              'lib/${import.substring('package:$packageName/'.length)}';
          final factories = switch (builder) {
            {'builder_factories': final List<Object?> names} => names,
            {'builder_factory': final String name} => [name],
            _ => const <Object?>[],
          };
          for (final factory in factories.whereType<String>()) {
            yield* configRule(factory, [
              file,
            ], 'a builder factory in build.yaml');
          }
        }
      }
    }
  }
}

/// `key` is `package:name`.
typedef _Builder = ({String key, Map<Object?, Object?> definition});

/// Builders build_runner applies to the root package: by `auto_apply`,
/// `targets:`, or transitively by `applies_builders`.
Iterable<_Builder> _appliedBuilders(
  String rootPath,
  String? rootName,
  Map<Object?, Object?>? rootBuildYaml,
) {
  final defined = <String, _Builder>{};
  final applied = <String>{};
  void define(String package, Map<Object?, Object?>? buildYaml) {
    if (buildYaml?['builders'] case final Map<Object?, Object?> builders) {
      for (final MapEntry(:key, value: definition) in builders.entries) {
        if (key is String && definition is Map<Object?, Object?>) {
          final builder = (key: '$package:$key', definition: definition);
          defined[builder.key] = builder;
          final own = package == rootName;
          if (switch (definition['auto_apply']) {
            'all_packages' => true,
            'dependents' => !own,
            'root_package' => own,
            _ => false,
          }) {
            applied.add(builder.key);
          }
        }
      }
    }
  }

  if (rootName != null) {
    define(rootName, rootBuildYaml);
  }
  for (final (:name, :root) in resolvedPackages(rootPath)) {
    if (name != rootName) {
      define(name, readYamlMap(p.join(root, 'build.yaml')));
    }
  }

  if (rootBuildYaml?['targets'] case final Map<Object?, Object?> targets) {
    for (final target in targets.values) {
      if (target case {'builders': final Map<Object?, Object?> builders}) {
        for (final MapEntry(:key, value: config) in builders.entries) {
          if (key is! String) {
            continue;
          }
          final builder = _builderKey(key, rootName);
          switch (config) {
            case {'enabled': false}:
              applied.remove(builder);
            case {'enabled': true} || {'generate_for': _} || {'options': _}:
              applied.add(builder);
          }
        }
      }
    }
  }

  final pending = [...applied];
  while (pending.isNotEmpty) {
    if (defined[pending.removeLast()]?.definition['applies_builders']
        case final List<Object?> more) {
      for (final key in more.whereType<String>()) {
        if (applied.add(_builderKey(key, rootName))) {
          pending.add(_builderKey(key, rootName));
        }
      }
    }
  }
  return [for (final key in applied) ?defined[key]];
}

/// `pkg|name`, `:name` (root package) and `name` (`name:name`) to
/// `pkg:name`.
String _builderKey(String key, String? rootName) {
  final normalized = key.replaceFirst('|', ':');
  if (normalized.startsWith(':')) {
    return '$rootName$normalized';
  }
  return normalized.contains(':') ? normalized : '$normalized:$normalized';
}

/// source_gen and freezed accept `build_extensions` as an option.
Iterable<String> _buildExtensionOptions(
  Map<Object?, Object?>? buildYaml,
) sync* {
  if (buildYaml?['targets'] case final Map<Object?, Object?> targets) {
    for (final target in targets.values) {
      if (target case {'builders': final Map<Object?, Object?> builders}) {
        for (final builder in builders.values) {
          if (builder case {
            'options': {'build_extensions': final Map<Object?, Object?> ext},
          }) {
            yield* outputGlobs(ext);
          }
        }
      }
    }
  }
}

final _captureGroup = RegExp(r'\{\{\w*\}\}');

/// Mirrors package:build's `expectedOutputs`.
Iterable<String> outputGlobs(Map<Object?, Object?> buildExtensions) sync* {
  for (final MapEntry(key: input, value: outputs) in buildExtensions.entries) {
    if (input is! String) {
      continue;
    }
    final dartOutputs = switch (outputs) {
      final String one => [one],
      final List<Object?> many => many.whereType<String>(),
      _ => const <String>[],
    }.where((output) => output.endsWith('.dart') && output != '.dart');
    for (final output in dartOutputs) {
      if (_captureGroup.hasMatch(input)) {
        final glob = output.splitMapJoin(
          _captureGroup,
          onMatch: (_) => '**',
          onNonMatch: escapeGlob,
        );
        final wholePath = input.startsWith('^') || input.startsWith('{{');
        yield wholePath ? glob : '**$glob';
      } else if (input.startsWith('^') || input == r'$package$') {
        yield escapeGlob(output);
      } else if (input == r'$lib$') {
        yield 'lib/${escapeGlob(output)}';
      } else {
        yield '**${escapeGlob(output)}';
      }
    }
  }
}
