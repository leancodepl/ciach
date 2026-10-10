import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns a rule for Serverpod endpoints. The dispatcher that Serverpod
/// generates calls the public methods of every subclass of `Endpoint`. It has
/// done so since Serverpod 0.8.0.
Iterable<EntryPoint> serverpodEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('serverpod')) {
    yield .publicMethodsOfSubclasses(
      'Endpoint',
      reason: 'called by the Serverpod dispatcher',
    );
  }
}
