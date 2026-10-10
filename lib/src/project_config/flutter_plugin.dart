import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// `registerWith` on each platform's `dartPluginClass`, and on the web
/// platform's `pluginClass`; any other `pluginClass` is native. Covers Flutter
/// up to 3.27, which added `dartFileName`.
Iterable<EntryPoint> flutterPluginEntryPoints(Pubspec pubspec) => [
  if (pubspec.yaml?['flutter'] case {
    'plugin': {'platforms': final Map<Object?, Object?> platforms},
  })
    for (final MapEntry(key: platform, value: config) in platforms.entries)
      if (config is Map<Object?, Object?>)
        ..._pluginClassesOf(platform, config),
];

Iterable<EntryPoint> _pluginClassesOf(
  Object? platform,
  Map<Object?, Object?> config,
) => [
  if (config case {'dartPluginClass': final String plugin})
    ..._registerWith(plugin, config['dartFileName'], platform),
  if ((platform, config) case ('web', {'pluginClass': final String plugin}))
    ..._registerWith(plugin, config['fileName'], platform),
];

Iterable<EntryPoint> _registerWith(
  String plugin,
  Object? fileName,
  Object? platform,
) => configRule('$plugin.registerWith', [
  if (fileName is String) 'lib/$fileName' else 'lib/**',
], 'called by Flutter to register the $platform plugin');
