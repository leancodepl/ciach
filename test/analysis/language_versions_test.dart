/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/analysis/language_versions.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = .systemTemp.createTempSync('ciach_language_versions_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  final newer = LanguageVersion(
    newestLanguageVersion.major,
    newestLanguageVersion.minor + 1,
  );

  /// Writes a package config to the root that gives each package of
  /// [versions], by its directory, its language version, and returns a file
  /// in each package.
  List<String> packagesWith(Map<String, LanguageVersion> versions) {
    String nameOf(String dir) => dir == '.' ? 'app' : p.basename(dir);
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        packageConfig(
          {for (final dir in versions.keys) nameOf(dir): dir},
          languageVersions: {
            for (final MapEntry(key: dir, value: version) in versions.entries)
              nameOf(dir): '$version',
          },
        ),
      );
    return [
      for (final dir in versions.keys)
        p.join(tempDir.path, dir, 'lib', 'a.dart'),
    ];
  }

  test(
    'throws for the packages that use a newer language version than the analyzer, with their versions',
    () {
      final paths = packagesWith({
        '.': newer,
        'packages/old': .new(3, 0),
        'packages/new': newer,
      });

      expect(
        () => checkLanguageVersions(paths, tempDir.path),
        throwsA(
          isA<UnsupportedLanguageVersionException>().having(
            (e) => e.packages,
            'packages',
            {'.': newer, 'packages/new': newer},
          ),
        ),
      );
    },
  );

  test('accepts packages that use the newest language version or older', () {
    final paths = packagesWith({
      '.': newestLanguageVersion,
      'packages/old': .new(3, 0),
    });

    expect(() => checkLanguageVersions(paths, tempDir.path), returnsNormally);
  });

  test(
    'the error names the newest supported version, each package, and how to upgrade',
    () {
      final error = UnsupportedLanguageVersionException({
        '.': .new(4, 1),
        'packages/app': .new(4, 0),
      });

      expect(
        error.message,
        '''
The `analyzer` package that ciach uses supports Dart language versions up to $newestLanguageVersion, and these packages use a newer one:
  . (4.1)
  packages/app (4.0)
Upgrade ciach and its analyzer: run `dart pub upgrade ciach analyzer` in a project that depends on ciach, or `dart install ciach` again.''',
      );
    },
  );
}
