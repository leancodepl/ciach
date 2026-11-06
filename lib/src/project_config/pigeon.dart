/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/source/directives.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/packages.dart';

/// Returns a rule that keeps what Pigeon reads from the input files among
/// [dartFiles], the Dart files of the package in [packagePath].
/// `dart run pigeon --input <file>` reads such a file and generates code from
/// it, so nothing imports it. An input file is a Dart file that imports
/// `package:pigeon/pigeon.dart`, the only import that Pigeon allows in it.
Iterable<EntryPoint> pigeonEntryPoints(
  String packagePath,
  Pubspec pubspec,
  List<String> dartFiles,
) sync* {
  if (!pubspec.dependencies.contains('pigeon')) {
    return;
  }
  final inputs = [
    for (final path in dartFiles)
      if (_importsPigeon(path)) escapeGlob(relativePosix(path, packagePath)),
  ]..sort();
  if (inputs.isNotEmpty) {
    yield PigeonInputEntryPoint(files: inputs);
  }
}

/// Whether the Dart file at [path] imports `package:pigeon/pigeon.dart`.
bool _importsPigeon(String path) {
  final content = readSource(path);
  // Only a file that names the library is parsed: stripping comments is slow.
  return content != null &&
      content.contains(_pigeonLibrary) &&
      Directive.allIn(content).any(
        (directive) =>
            directive.keyword == 'import' &&
            directive.uris.any(
              (uri) => uri.namedGroup('uri') == _pigeonLibrary,
            ),
      );
}

const _pigeonLibrary = 'package:pigeon/pigeon.dart';
