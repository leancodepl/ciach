import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the `registerWith` methods that Flutter calls to register a plugin.
/// There is one on the `dartPluginClass` of each platform, and one on the
/// `pluginClass` of the web platform. On the other platforms, `pluginClass`
/// names a native class (Flutter 3.27+).
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
