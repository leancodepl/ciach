/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:ciach/src/model/finder_options.dart';
import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Directory names that never contain source worth analyzing.
const _skippedDirs = {
  '.dart_tool',
  '.git',
  'build',
  '.fvm',
  'node_modules',
  '.widget_preview',
};

/// Filename suffixes produced by common Dart/Flutter code generators.
const _generatedSuffixes = [
  '.g.dart',
  '.freezed.dart',
  '.gr.dart',
  '.config.dart',
  '.mocks.dart',
  '.gen.dart',
  '.pb.dart',
  '.pbenum.dart',
  '.pbjson.dart',
  '.pbserver.dart',
  '.chopper.dart',
];

/// The `.dart` files under the root, sorted by their paths alone; see
/// [dartFilesByPath].
typedef DartFilePaths = ({
  /// The files that the include and exclude globs select.
  List<String> selected,

  /// The files that the globs leave out. A banner that marks one generated
  /// still makes it reference-only.
  List<String> unselected,

  /// The files that their name or a generated glob marks as generated,
  /// whichever globs select them. None when generated files are scanned.
  List<String> generated,
});

/// The `.dart` files under the configured root, outside the skipped
/// directories: those that their name or a generated glob marks as
/// generated, and the others by whether the include and exclude globs select
/// them. The paths are absolute, normalized and sorted.
DartFilePaths dartFilesByPath(FinderOptions options) {
  // Already absolute and normalized: `FinderOptions` is the only way in.
  final rootPath = options.rootPath;
  final context = p.Context(style: .posix);
  final includeGlobs = _globs(options.includeGlobs, context);
  final excludeGlobs = _globs(options.excludeGlobs, context);
  final generatedGlobs = _globs(options.additionalGeneratedGlobs, context);

  final selected = <String>[];
  final unselected = <String>[];
  final generated = <String>[];
  for (final file in Directory(
    rootPath,
  ).listSync(recursive: true, followLinks: false).whereType<File>()) {
    if (!file.path.endsWith('.dart')) {
      continue;
    }
    final absolute = p.normalize(file.absolute.path);
    // Path relative to root, in POSIX form so globs behave predictably.
    final relative = context.joinAll(
      p.split(p.relative(absolute, from: rootPath)),
    );
    if (isInSkippedDir(relative)) {
      continue;
    }
    if (!options.includeGenerated &&
        (generatedGlobs.any((glob) => glob.matches(relative)) ||
            _generatedSuffixes.any(p.basename(relative).endsWith))) {
      generated.add(absolute);
    } else if (_isSelected(relative, includeGlobs, excludeGlobs)) {
      selected.add(absolute);
    } else {
      unselected.add(absolute);
    }
  }
  return (
    selected: selected..sort(),
    unselected: unselected..sort(),
    generated: generated..sort(),
  );
}

/// Whether [relative] matches an [include] glob, when there are any, and no
/// [exclude] glob.
bool _isSelected(String relative, List<Glob> include, List<Glob> exclude) =>
    (include.isEmpty || include.any((glob) => glob.matches(relative))) &&
    exclude.none((glob) => glob.matches(relative));

List<Glob> _globs(List<String> patterns, p.Context context) => [
  for (final pattern in patterns) .new(pattern, context: context),
];

bool isInSkippedDir(String relativePath) =>
    p.split(relativePath).any(_skippedDirs.contains);
