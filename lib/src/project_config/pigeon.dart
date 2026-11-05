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

/// Returns a rule that keeps every declaration in the Pigeon input files of
/// the package in [packagePath]. `dart run pigeon --input <file>` reads such
/// a file and generates code from it, so nothing imports it. An input file is
/// a Dart file that imports `package:pigeon/`.
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
    yield .everyDeclaration(
      reason: 'in a Pigeon input file, which Pigeon generates code from',
      files: inputs,
    );
  }
}

/// Whether the Dart file at [path] imports a library of `package:pigeon`.
bool _importsPigeon(String path) {
  final content = readSource(path);
  // Only a file that names the package is parsed: stripping comments is slow.
  return content != null &&
      content.contains(_pigeonUri) &&
      Directive.allIn(content).any(
        (directive) =>
            directive.keyword == 'import' &&
            directive.uris.any(
              (uri) => uri.namedGroup('uri')!.startsWith(_pigeonUri),
            ),
      );
}

const _pigeonUri = 'package:pigeon/';
