import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Serverpod's generated dispatcher calls the public methods of `Endpoint`
/// subclasses, as it has since 0.8.0.
Iterable<EntryPoint> serverpodEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('serverpod')) {
    yield .publicMethodsOfSubclasses(
      'Endpoint',
      reason: 'called by the Serverpod dispatcher',
    );
  }
}
