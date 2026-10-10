import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// custom_lint calls `createPlugin` in `lib/<package>.dart`, as it has since
/// custom_lint_builder 0.1.0.
Iterable<EntryPoint> customLintEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('custom_lint_builder')) {
    if (pubspec.name case final name?) {
      yield* configRule('createPlugin', [
        'lib/$name.dart',
      ], 'called by custom_lint');
    }
  }
}
