import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

Iterable<EntryPoint> dartFrogEntryPoints(Pubspec pubspec) sync* {
  if (!pubspec.dependencies.contains('dart_frog')) {
    return;
  }
  yield* configRule('onRequest', ['routes/**'], 'a dart_frog route handler');
  yield* configRule('middleware', [
    'routes/**_middleware.dart',
  ], 'a dart_frog middleware');
  for (final hook in const ['init', 'run']) {
    yield* configRule(hook, ['main.dart'], 'a dart_frog server hook');
  }
}
