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

import 'package:ciach/src/models.dart';
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

  /// Generated files excluded from [candidates] (because `includeGenerated` is
  /// off) that are nonetheless opened to keep the analysis server's resolved
  /// units warm — so a declaration referenced *only* from generated code is
  /// not misreported as unused once the server evicts the unopened unit. Empty
  /// when generated files are already scan candidates.
  List<String> warmOnly,
});

/// Discovers the `.dart` files under the configured root that should be
/// scanned for declarations, honouring include/exclude globs and
/// generated-file rules.
///
/// Results are returned as absolute file paths, sorted for stable output.
List<String> discoverDartFiles(FinderOptions options) =>
    discoverDartFilesSplit(options).candidates;

/// Like [discoverDartFiles], but also returns the generated files that are
/// excluded from the scan so the caller can still open them for reference
/// resolution — see the `warmOnly` field of [DiscoveredDartFiles].
///
/// The warm-only set is deliberately *not* filtered by include/exclude globs:
/// its only purpose is to let reference queries resolve, and a reference can
/// legitimately live in a generated file the user isn't scanning. Files inside
/// skipped directories (`build/`, `.dart_tool/`, …) are still excluded.
DiscoveredDartFiles discoverDartFilesSplit(FinderOptions options) {
  final rootPath = p.normalize(p.absolute(options.rootPath));
  final root = Directory(rootPath);
  final context = p.Context(style: p.Style.posix);

  final includeGlobs = [
    for (final pattern in options.includeGlobs) Glob(pattern, context: context),
  ];
  final excludeGlobs = [
    for (final pattern in options.excludeGlobs) Glob(pattern, context: context),
  ];

  final candidates = <String>[];
  final warmOnly = <String>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final absolute = p.normalize(entity.absolute.path);
    // Path relative to root, in POSIX form so globs behave predictably.
    final relative = context.joinAll(
      p.split(p.relative(absolute, from: rootPath)),
    );

    if (_isInSkippedDir(relative)) {
      continue;
    }
    if (!options.includeGenerated &&
        _isGenerated(entity, relative, options.additionalGeneratedSuffixes)) {
      warmOnly.add(absolute);
      continue;
    }
    if (includeGlobs.isNotEmpty &&
        !includeGlobs.any((glob) => glob.matches(relative))) {
      continue;
    }
    if (excludeGlobs.any((glob) => glob.matches(relative))) {
      continue;
    }

    candidates.add(absolute);
  }

  candidates.sort();
  warmOnly.sort();
  return (candidates: candidates, warmOnly: warmOnly);
}

bool _isInSkippedDir(String relativePath) =>
    p.split(relativePath).any(_skippedDirs.contains);

bool _isGenerated(
  File file,
  String relativePath,
  List<String> additionalSuffixes,
) {
  final name = p.basename(relativePath);
  if (_generatedSuffixes.any(name.endsWith) ||
      additionalSuffixes.any(name.endsWith)) {
    return true;
  }
  // Fall back to the conventional generated-code banner near the top of the
  // file. Generators emit it within the first line or two.
  return _readPrefix(
    file,
    300,
  ).contains('GENERATED CODE - DO NOT MODIFY BY HAND');
}

String _readPrefix(File file, int maxChars) {
  try {
    final content = file.readAsStringSync();
    return content.length <= maxChars
        ? content
        : content.substring(0, maxChars);
  } on Object {
    return '';
  }
}
