import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the entry point of an analyzer plugin. The analysis server loads
/// the `plugin` variable from `lib/main.dart`. It has done so since
/// analysis_server_plugin 0.2.0.
Iterable<EntryPoint> analysisServerPluginEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('analysis_server_plugin')) {
    yield* configRule('plugin', [
      'lib/main.dart',
    ], 'called by the analysis server');
  }
}
