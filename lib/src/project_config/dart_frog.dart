import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

Iterable<EntryPoint> dartFrogEntryPoints(Pubspec pubspec) sync* {
  if (!pubspec.dependencies.contains('dart_frog')) {
    return;
  }
  yield* configRule('onRequest', ['routes/**'], 'called by dart_frog');
  yield* configRule('middleware', [
    'routes/**_middleware.dart',
  ], 'called by dart_frog');
  for (final hook in const ['init', 'run']) {
    yield* configRule(hook, ['main.dart'], 'called by dart_frog');
  }
}
