/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The newest Dart language version that the analyzer supports, such as
/// 3.15 for analyzer 14.7.0.
final LanguageVersion newestLanguageVersion = _newestLanguageVersion();

/// Returns the version that the analyzer parses code that has no language
/// version with, except for analyzer 13.0.0: it parses with 3.13, but still
/// treats primary constructors, which Dart 3.13 releases, as an experiment,
/// so it supports 3.12.
LanguageVersion _newestLanguageVersion() {
  final version = parseString(content: '').unit.languageVersion.package;
  return version.major == 3 &&
          version.minor == 13 &&
          !FeatureSet.latestLanguageVersion().isEnabled(.primary_constructors)
      ? .new(3, 12)
      : .new(version.major, version.minor);
}

/// Throws an [UnsupportedLanguageVersionException] when a package that holds
/// one of [paths] uses a newer Dart language version than the analyzer
/// supports. The language version of a package is the one that its package
/// config gives it, the lower bound of its `sdk:` constraint.
void checkLanguageVersions(Iterable<String> paths, String rootPath) {
  final packages = PackageResolver();
  final newer = {
    for (final path in paths)
      if (packages.configOf(p.dirname(path))?.packageOf(.file(path))
          case Package(:final root, languageVersion: final version?)
          when version > newestLanguageVersion)
        relativePosix(root.toFilePath(), rootPath): version,
  };
  if (newer.isNotEmpty) {
    throw UnsupportedLanguageVersionException(newer);
  }
}

/// Thrown when some scanned packages use a newer Dart language version than
/// the analyzer supports, so it would misread their code.
final class UnsupportedLanguageVersionException implements Exception {
  const UnsupportedLanguageVersionException(this.packages);

  /// The language version of each package, by the package's path relative to
  /// the root and separated by `/`. The root itself is `.`.
  final Map<String, LanguageVersion> packages;

  String get message =>
      '''
The `analyzer` package that ciach uses supports Dart language versions up to $newestLanguageVersion, and these packages use a newer one:
${[for (final MapEntry(key: package, value: version) in packages.entries) '  $package ($version)'].join('\n')}
Upgrade ciach and its analyzer: run `dart pub upgrade ciach analyzer` in a project that depends on ciach, or `dart install ciach` again.''';

  @override
  String toString() => message;
}
