import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns a rule for the classes that have Serverpod's `Endpoint` among
/// their supertypes, and for their public methods, which the dispatcher that
/// Serverpod generates calls.
Iterable<EntryPoint> serverpodEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('serverpod')) {
    yield .publicMethodsOfSubclasses(
      'Endpoint',
      package: 'serverpod',
      reason: 'called by the Serverpod dispatcher',
    );
  }
}
