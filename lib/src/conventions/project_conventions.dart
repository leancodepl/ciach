import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

final _log = Logger('ciach.finder');

/// Entry points and generated files declared by pubspec.yaml, build.yaml and
/// l10n.yaml. Unparsable files are ignored.
final class ProjectConventions {
  const ProjectConventions({
    this.entryPoints = const [],
    this.generatedGlobs = const [],
    this.serverpod = false,
  });

  factory ProjectConventions.read(String rootPath) {
    final pubspec = _readYaml(p.join(rootPath, 'pubspec.yaml'));
    final buildYaml = _readYaml(p.join(rootPath, 'build.yaml'));
    final name = switch (pubspec?['name']) {
      final String name => name,
      _ => null,
    };
    final dependencies = {
      for (final section in const ['dependencies', 'dev_dependencies'])
        if (pubspec?[section] case final Map<Object?, Object?> deps)
          ...deps.keys.whereType<String>(),
    };

    return ProjectConventions(
      entryPoints: [
        ..._pluginClasses(pubspec),
        if (name != null) ..._builderFactories(buildYaml, name),
        ..._frameworkEntryPoints(dependencies, name),
      ],
      generatedGlobs: {
        for (final builder in _appliedBuilders(rootPath, name, buildYaml))
          if (builder.definition case {
            'build_to': 'source',
            'build_extensions': final Map<Object?, Object?> extensions,
          })
            ...outputGlobs(extensions),
        ..._buildExtensionOptions(buildYaml),
        ..._l10nOutputs(rootPath),
      }.toList(),
      serverpod: dependencies.contains('serverpod'),
    ).._narrate();
  }

  static const none = ProjectConventions();

  final List<EntryPoint> entryPoints;

  /// POSIX, relative to the package root.
  final List<String> generatedGlobs;

  final bool serverpod;

  void _narrate() {
    for (final rule in entryPoints) {
      _log.config(
        'Entry point from the project config: $rule (${rule.reason}).',
      );
    }
    if (generatedGlobs.isNotEmpty) {
      _log.config(
        'Generated files from the project config: ${generatedGlobs.join(', ')}.',
      );
    }
    if (serverpod) {
      _log.config(
        'Depends on serverpod: public methods of `Endpoint` subclasses are '
        'entry points.',
      );
    }
  }
}

Map<Object?, Object?>? _readYaml(String path) {
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

/// Non-web `pluginClass` is native.
Iterable<EntryPoint> _pluginClasses(Map<Object?, Object?>? pubspec) sync* {
  if (pubspec?['flutter'] case {
    'plugin': {'platforms': final Map<Object?, Object?> platforms},
  }) {
    for (final MapEntry(key: platform, value: config) in platforms.entries) {
      if (config is! Map<Object?, Object?>) {
        continue;
      }
      if (config case {'dartPluginClass': final String plugin}) {
        yield* _registerWith(plugin, config['dartFileName'], platform);
      }
      if (platform == 'web') {
        if (config case {'pluginClass': final String plugin}) {
          yield* _registerWith(plugin, config['fileName'], platform);
        }
      }
    }
  }
}

Iterable<EntryPoint> _registerWith(
  String plugin,
  Object? fileName,
  Object? platform,
) => _rules('$plugin.registerWith', [
  if (fileName is String) 'lib/$fileName' else 'lib/**',
], 'the $platform plugin class in pubspec.yaml');

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
            yield* _rules(factory, [file], 'a builder factory in build.yaml');
          }
        }
      }
    }
  }
}

Iterable<EntryPoint> _frameworkEntryPoints(
  Set<String> dependencies,
  String? packageName,
) sync* {
  if (dependencies.contains('dart_frog')) {
    yield* _rules('onRequest', ['routes/**'], 'a dart_frog route handler');
    yield* _rules('middleware', [
      'routes/**_middleware.dart',
    ], 'a dart_frog middleware');
    for (final hook in const ['init', 'run']) {
      yield* _rules(hook, ['main.dart'], 'a dart_frog server hook');
    }
  }
  if (dependencies.contains('analysis_server_plugin')) {
    yield* _rules('plugin', [
      'lib/main.dart',
    ], 'the analyzer plugin the analysis server loads');
  }
  if (dependencies.contains('custom_lint_builder') && packageName != null) {
    yield* _rules('createPlugin', [
      'lib/$packageName.dart',
    ], 'the custom_lint plugin entry point');
  }
}

Iterable<EntryPoint> _rules(
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
  for (final (:name, :root) in _resolvedPackages(rootPath)) {
    if (name != rootName) {
      define(name, _readYaml(p.join(root, 'build.yaml')));
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

/// From the nearest package_config.json; a pub workspace keeps it at its
/// root.
Iterable<({String name, String root})> _resolvedPackages(
  String rootPath,
) sync* {
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
          onNonMatch: _escapeGlob,
        );
        final wholePath = input.startsWith('^') || input.startsWith('{{');
        yield wholePath ? glob : '**$glob';
      } else if (input.startsWith('^') || input == r'$package$') {
        yield _escapeGlob(output);
      } else if (input == r'$lib$') {
        yield 'lib/${_escapeGlob(output)}';
      } else {
        yield '**${_escapeGlob(output)}';
      }
    }
  }
}

String _escapeGlob(String literal) =>
    literal.replaceAllMapped(RegExp(r'[*?\[\]{},\\]'), (m) => '\\${m[0]}');

/// gen-l10n output has no banner.
Iterable<String> _l10nOutputs(String rootPath) sync* {
  final file = File(p.join(rootPath, 'l10n.yaml'));
  if (!file.existsSync()) {
    return;
  }
  final config = _readYaml(file.path) ?? const {};
  if (config['synthetic-package'] == true) {
    return;
  }
  final arbDir = switch (config['arb-dir']) {
    final String dir => dir,
    _ => 'lib/l10n',
  };
  final outputDir = switch (config['output-dir']) {
    final String dir => dir,
    _ => arbDir,
  };
  final outputFile = switch (config['output-localization-file']) {
    final String name => name,
    _ => 'app_localizations.dart',
  };
  final stem = p.posix.withoutExtension(outputFile);
  final dir = p.posix.normalize(outputDir);
  yield '${_escapeGlob(dir)}/${_escapeGlob(stem)}{,_*}.dart';
}
