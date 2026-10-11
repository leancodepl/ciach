import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the `plugin` variable in `lib/main.dart`, which the analysis
/// server loads (analysis_server_plugin 0.2.0+).
Iterable<EntryPoint> analysisServerPluginEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('analysis_server_plugin')) {
    yield* configRule('plugin', [
      'lib/main.dart',
    ], 'called by the analysis server');
  }
}
