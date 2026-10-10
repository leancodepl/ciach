import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// The functions dart_frog calls: route handlers, middleware and the server
/// hooks in `main.dart`. This follows dart_frog_cli up to 0.3.4, the version
/// that added `init`.
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
