import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory root;

  setUp(() => root = .systemTemp.createTempSync('ciach_unresolved_'));

  tearDown(() => root.deleteSync(recursive: true));

  String abs(String relative) =>
      p.joinAll([root.path, ...p.posix.split(relative)]);

  void write(String path, [String contents = '']) => File(abs(path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  /// The root-relative paths of the unresolved packages that hold [files].
  List<String> unresolved(List<String> files) => [
    for (final package in unresolvedPackages(files.map(abs), root.path))
      relativePosix(package, root.path),
  ];

  group('unresolvedPackages', () {
    test('a package with its own package config is resolved', () {
      write('pubspec.yaml', 'name: app\n');
      write('.dart_tool/package_config.json', packageConfig({'app': '.'}));

      expect(unresolved(['lib/a.dart', 'test/a_test.dart']), isEmpty);
    });

    test('a package without its own package config is unresolved', () {
      write('pubspec.yaml', 'name: app\n');

      expect(unresolved(['lib/a.dart', 'test/a_test.dart']), ['.']);
    });

    test('a nested package needs its own package config', () {
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

    test('a workspace member listed in the workspace config is resolved', () {
      write('pubspec.yaml', 'name: root\nworkspace: [packages/ds]\n');
      write(
        '.dart_tool/package_config.json',
        packageConfig({'root': '.', 'ds': 'packages/ds'}),
      );
      write('packages/ds/pubspec.yaml', 'name: ds\nresolution: workspace\n');

      expect(unresolved(['packages/ds/lib/ds.dart']), isEmpty);
    });

    test('a workspace member is unresolved if the workspace has no config', () {
      write('pubspec.yaml', 'name: root\nworkspace: [packages/ds]\n');
      write('packages/ds/pubspec.yaml', 'name: ds\nresolution: workspace\n');

      expect(unresolved(['packages/ds/lib/ds.dart']), ['packages/ds']);
    });

    test('a workspace member the workspace config omits is unresolved', () {
      write('pubspec.yaml', 'name: root\nworkspace: [packages/ds]\n');
      write('.dart_tool/package_config.json', packageConfig({'root': '.'}));
      write('packages/ds/pubspec.yaml', 'name: ds\nresolution: workspace\n');

      expect(unresolved(['packages/ds/lib/ds.dart']), ['packages/ds']);
    });

    test('ignores a file outside any package', () {
      expect(unresolved(['tool/script.dart']), isEmpty);
    });

    test('ignores a package whose pubspec is above the scanned root', () {
      write('pubspec.yaml', 'name: outer\n');
      final scripts = abs('scripts');

      expect(unresolvedPackages([p.join(scripts, 'a.dart')], scripts), isEmpty);
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

    test('throws before analysis when a scanned package is unresolved', () {
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

    test('runs when the unresolved package is excluded', () {
      expect(
        Ciach(
          .new(rootPath: root.path, excludeGlobs: ['packages/ds/**']),
        ).run(),
        completion(
          isA<FinderResult>().having((r) => r.filesScanned, 'filesScanned', 1),
        ),
      );
    });
  });
}
