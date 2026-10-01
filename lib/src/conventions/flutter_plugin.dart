import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/project_files.dart';

/// Non-web `pluginClass` is native.
Iterable<EntryPoint> flutterPluginEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.yaml?['flutter'] case {
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
) => configRule('$plugin.registerWith', [
  if (fileName is String) 'lib/$fileName' else 'lib/**',
], 'the $platform plugin class in pubspec.yaml');
