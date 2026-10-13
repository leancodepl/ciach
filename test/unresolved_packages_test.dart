import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/paths.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

void main() {
  late Directory root;

  setUp(() => root = .systemTemp.createTempSync('ciach_unresolved_'));

  tearDown(() => root.deleteSync(recursive: true));

  String abs(String relative) =>
      p.joinAll([root.path, ...p.posix.split(relative)]);

  void write(String path, [String contents = '']) => File(abs(path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// The packages of [files] pub has not resolved, root-relative.
  List<String> unresolved(List<String> files) => [
    for (final package in unresolvedPackages(files.map(abs)))
      relativePosix(package, root.path),
  ];

  group('unresolvedPackages', () {
    test('a package with its own package config is resolved', () {
      write('pubspec.yaml', 'name: app\n');
      write('.dart_tool/package_config.json', packageConfig({'app': '.'}));

      expect(unresolved(['lib/a.dart', 'test/a_test.dart']), isEmpty);
    });

    test('a package without one is not', () {
      write('pubspec.yaml', 'name: app\n');

      expect(unresolved(['lib/a.dart', 'test/a_test.dart']), ['.']);
    });

    test("a nested path dependency is not covered by its parent's config", () {
      write(
        'pubspec.yaml',
        'name: app\ndependencies: {ds: {path: packages/ds}}\n',
      );
      write(
        '.dart_tool/package_config.json',
        packageConfig({'app': '.', 'ds': 'packages/ds'}),
      );
      write('packages/ds/pubspec.yaml', 'name: ds\n');

      expect(
        unresolved([
          'lib/a.dart',
          'packages/ds/lib/ds.dart',
          'packages/ds/test/helpers.dart',
        ]),
        ['packages/ds'],
      );
    });

    test("a workspace member is covered by the workspace's config", () {
      write('pubspec.yaml', 'name: root\nworkspace: [packages/ds]\n');
      write(
        '.dart_tool/package_config.json',
        packageConfig({'root': '.', 'ds': 'packages/ds'}),
      );
      write('packages/ds/pubspec.yaml', 'name: ds\nresolution: workspace\n');

      expect(unresolved(['packages/ds/lib/ds.dart']), isEmpty);
    });

    test('a workspace member of an unresolved workspace is not resolved', () {
      write('pubspec.yaml', 'name: root\nworkspace: [packages/ds]\n');
      write('packages/ds/pubspec.yaml', 'name: ds\nresolution: workspace\n');

      expect(unresolved(['packages/ds/lib/ds.dart']), ['packages/ds']);
    });

    test('a file under no pubspec belongs to no package', () {
      expect(unresolved(['tool/script.dart']), isEmpty);
    });
  });

  group('Ciach.run', () {
    setUp(() {
      write('pubspec.yaml', 'name: app\n');
      write('.dart_tool/package_config.json', packageConfig({'app': '.'}));
      write('lib/a.dart', 'void a() {}\n');
      write('packages/ds/pubspec.yaml', 'name: ds\n');
      write('packages/ds/test/helpers.dart', 'void helper() {}\n');
    });

    test('fails before analysis on a scanned unresolved package', () {
      expect(
        Ciach(.new(rootPath: root.path)).run(),
        throwsA(
          isA<UnresolvedPackagesException>().having(
            (e) => e.packages,
            'packages',
            ['packages/ds'],
          ),
        ),
      );
    });

    test('skips an unresolved package whose files are excluded', () {
      // With nothing left to scan, the run ends before starting a server, so
      // getting past the check is enough to show it.
      expect(
        Ciach(
          .new(
            rootPath: root.path,
            includeGlobs: ['packages/**'],
            excludeGlobs: ['packages/ds/**'],
          ),
        ).run(),
        completion(
          isA<FinderResult>().having((r) => r.filesScanned, 'filesScanned', 0),
        ),
      );
    });
  });
}
