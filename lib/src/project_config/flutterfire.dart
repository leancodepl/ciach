import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// Returns globs for the Dart files `flutterfire configure` wrote, as the
/// `firebase.json` in [packagePath] records them. Their names are whatever
/// `--out` said, `lib/firebase_options.dart` by default.
Iterable<String> flutterFireGeneratedGlobs(String packagePath) sync* {
  final file = File(p.join(packagePath, 'firebase.json'));
  if (!file.existsSync()) {
    return;
  }
  final Object? json;
  try {
    json = jsonDecode(file.readAsStringSync());
  } on FormatException {
    return;
  } on FileSystemException {
    return;
  }
  if (json case {
    'flutter': {'platforms': {'dart': final Map<String, Object?> outputs}},
  }) {
    for (final output in outputs.keys) {
      yield escapeGlob(p.posix.normalize(output));
    }
  }
}
