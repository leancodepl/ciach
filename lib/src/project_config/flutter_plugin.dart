import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the `registerWith` methods that Flutter calls to register a plugin.
/// There is one on the `dartPluginClass` of each platform, and one on the
/// `pluginClass` of the web platform. On the other platforms, `pluginClass`
/// names a native class.
Iterable<EntryPoint> flutterPluginEntryPoints(Pubspec pubspec) => [
  if (pubspec.yaml?['flutter'] case {
    'plugin': {'platforms': final Map<Object?, Object?> platforms},
  })
    for (final MapEntry(key: platform, :value) in platforms.entries)
      if (value case final Map<Object?, Object?> config)
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
  switch (fileName) {
    final String name => 'lib/$name',
    _ => 'lib/**',
  },
], 'called by Flutter to register the $platform plugin');
