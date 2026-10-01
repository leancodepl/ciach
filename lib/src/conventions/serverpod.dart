import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/project_files.dart';

Iterable<EntryPoint> serverpodEntryPoints(Pubspec pubspec) sync* {
  if (pubspec.dependencies.contains('serverpod')) {
    yield .publicMethodsOfSubclasses(
      'Endpoint',
      reason: 'a Serverpod endpoint method, called by the generated dispatcher',
    );
  }
}
