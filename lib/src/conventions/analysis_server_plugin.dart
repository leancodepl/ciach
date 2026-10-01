import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/project_files.dart';

Iterable<EntryPoint> analysisServerPluginEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('analysis_server_plugin')) {
    yield* configRule('plugin', [
      'lib/main.dart',
    ], 'the analyzer plugin the analysis server loads');
  }
}
