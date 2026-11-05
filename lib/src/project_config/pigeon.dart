/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/source/directives.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Returns a rule that keeps what Pigeon reads from the input files of the
/// package in [packagePath]. `dart run pigeon --input <file>` reads such a
/// file and generates code from it, so nothing imports it. An input file is
/// a Dart file that imports `package:pigeon/pigeon.dart`, the only import
/// that Pigeon allows in it.
Iterable<EntryPoint> pigeonEntryPoints(
  String packagePath,
  Pubspec pubspec,
) sync* {
  if (!pubspec.dependencies.contains('pigeon')) {
    return;
  }
  final tree = scanPackageTree(packagePath);
  // A nested package reads its own input files.
  final nestedPackages = [
    for (final libDir in tree.libDirs)
      if (!p.equals(p.dirname(libDir), packagePath)) p.dirname(libDir),
  ];
  final inputs = [
    for (final path in tree.dartFiles)
      if (nestedPackages.none((dir) => p.isWithin(dir, path)) &&
          _importsPigeon(path))
        escapeGlob(
          p.posix.joinAll(p.split(p.relative(path, from: packagePath))),
        ),
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
