import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// Returns the `plugin` variable in `lib/main.dart`, which the analysis
/// server loads (analysis_server_plugin 0.2.0+). [loadedAsPlugin] says an
/// `analysis_options.yaml` under the root loads the package as a plugin, for
/// one that depends on analysis_server_plugin only through another package.
Iterable<EntryPoint> analysisServerPluginEntryPoints(
  Pubspec pubspec, {
  bool loadedAsPlugin = false,
}) sync* {
  if (loadedAsPlugin ||
      pubspec.dependencies.contains('analysis_server_plugin')) {
    yield* configRule('plugin', [
      'lib/main.dart',
    ], 'called by the analysis server');
  }
}

/// Returns the directories, absolute and normalized, of the plugins that
/// `analysis_options.yaml` in [dir] loads by `path:`.
Iterable<String> analyzerPluginDirs(String dir) sync* {
  final options = readYamlMap(p.join(dir, 'analysis_options.yaml'));
  if (options?['plugins'] case final Map<Object?, Object?> plugins) {
    for (final plugin in plugins.values) {
      if (plugin case {'path': final String path}) {
        yield p.normalize(p.absolute(dir, path));
      }
    }
  }
}
