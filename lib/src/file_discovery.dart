/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ciach/src/ignore_markers.dart';
import 'package:ciach/src/models.dart';
import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

/// Directory names that never contain source worth analyzing.
const _skippedDirs = {'.dart_tool', '.git', 'build', '.fvm', 'node_modules'};

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

/// The `.dart` files discovered under the configured root, split by role.
typedef DiscoveredDartFiles = ({
  /// Files whose declarations are scanned and reported as candidates.
  List<String> candidates,

  /// Generated files excluded from [candidates] but still opened to keep the
  /// analysis server's units warm, so a declaration referenced *only* from
  /// generated code isn't misreported as unused. Files marked
  /// `// ciach:ignore-file` are among them, even when generated files are
  /// candidates.
  List<String> warmOnly,

  /// The files of [warmOnly] that a `// ciach:ignore-file` marker put there.
  List<String> ignored,
});

/// Discovers the `.dart` files under the configured root that should be
/// scanned for declarations, honoring include/exclude globs and
/// generated-file rules.
///
/// Results are returned as absolute file paths, sorted for stable output.
List<String> discoverDartFiles(FinderOptions options) =>
    discoverDartFilesSplit(options).candidates;

/// Like [discoverDartFiles], but also returns the excluded generated files as
/// `warmOnly` (see [DiscoveredDartFiles]) so the caller can open them for
/// reference resolution.
///
/// The warm-only set is deliberately not filtered by include/exclude globs — a
/// reference can live in a generated file the user isn't scanning — though
/// skipped directories (`build/`, `.dart_tool/`, …) are still excluded.
DiscoveredDartFiles discoverDartFilesSplit(FinderOptions options) {
  // Already absolute and normalized: `FinderOptions` is the only way in.
  final rootPath = options.rootPath;
  final root = Directory(rootPath);
  final context = p.Context(style: .posix);

  final includeGlobs = _globs(options.includeGlobs, context);
  final excludeGlobs = _globs(options.excludeGlobs, context);
  final generatedGlobs = _globs(options.additionalGeneratedGlobs, context);

  final candidates = <String>[];
  final warmOnly = <String>[];
  final ignored = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final absolute = p.normalize(entity.absolute.path);
    // Path relative to root, in POSIX form so globs behave predictably.
    final relative = context.joinAll(
      p.split(p.relative(absolute, from: rootPath)),
    );

    if (isInSkippedDir(relative)) {
      continue;
    }
    // Read once, and only when a check needs it.
    late final source = _read(entity);
    if (!options.includeGenerated &&
        (generatedGlobs.any((glob) => glob.matches(relative)) ||
            _isGenerated(
              relative,
              () => source,
              options.additionalGeneratedSuffixes,
            ))) {
      warmOnly.add(absolute);
      continue;
    }
    if (!_isSelected(relative, includeGlobs, excludeGlobs)) {
      continue;
    }
    if (IgnoreMarkers.parse(source).ignoresFile) {
      warmOnly.add(absolute);
      ignored.add(absolute);
      continue;
    }

    candidates.add(absolute);
  }

  candidates.sort();
  warmOnly.sort();
  ignored.sort();
  return (candidates: candidates, warmOnly: warmOnly, ignored: ignored);
}

/// Whether [relative] matches an [include] glob, when there are any, and no
/// [exclude] glob.
bool _isSelected(String relative, List<Glob> include, List<Glob> exclude) =>
    (include.isEmpty || include.any((glob) => glob.matches(relative))) &&
    exclude.none((glob) => glob.matches(relative));

List<Glob> _globs(List<String> patterns, p.Context context) => [
  for (final pattern in patterns) Glob(pattern, context: context),
];

bool isInSkippedDir(String relativePath) =>
    p.split(relativePath).any(_skippedDirs.contains);

/// Whether the file at [relativePath] is generated: by its name, or by the
/// banner atop its [source].
bool _isGenerated(
  String relativePath,
  String Function() source,
  List<String> additionalSuffixes,
) {
  final name = p.basename(relativePath);
  if (_generatedSuffixes.any(name.endsWith) ||
      additionalSuffixes.any(name.endsWith)) {
    return true;
  }
  final content = source();
  return isGeneratedBanner(content.substring(0, min(content.length, 2000)));
}

/// The banner that build_runner writes at the top of a generated file. It is
/// matched anywhere in the first 300 characters of the file.
const _buildBanner = 'GENERATED CODE - DO NOT MODIFY BY HAND';

final _banner = RegExp(
  r'\b(?:auto-?)?generated\b.{0,200}?\b(?:do not|don.t|must not)\s+(?:\w+\s+)?(?:edit|modify)\b|\b(?:do not|don.t)\s+(?:edit|modify)\b.{0,200}?\bgenerated\b',
  caseSensitive: false,
);

/// Returns whether [source] starts with a banner that marks generated code.
/// Only the comments before the first declaration are read. Doc comments are
/// skipped, because a doc comment can mention generated code in a file that
/// is not generated.
bool isGeneratedBanner(String source) {
  if (source.substring(0, min(source.length, 300)).contains(_buildBanner)) {
    return true;
  }
  final comments = StringBuffer();
  var inBlock = false;
  for (final raw in const LineSplitter().convert(source)) {
    final line = raw.trim();
    if (inBlock) {
      comments.write(' $line');
      inBlock = !line.contains('*/');
    } else if (line.startsWith('///')) {
      continue;
    } else if (line.startsWith('//')) {
      comments.write(' $line');
    } else if (line.startsWith('/*')) {
      comments.write(' $line');
      inBlock = !line.substring(2).contains('*/');
    } else if (line.isNotEmpty) {
      break;
    }
  }
  return _banner.hasMatch(comments.toString());
}

/// The text of [file]; empty when it cannot be read.
String _read(File file) {
  try {
    return file.readAsStringSync();
  } on FileSystemException {
    return '';
  }
}
