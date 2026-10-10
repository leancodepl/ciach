import 'dart:io';

import 'package:ciach/src/packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  String path(String relative) => p.normalize(p.join(root.path, relative));

  setUp(() {
    root = .systemTemp.createTempSync('ciach_packages_');
    // A pub workspace: one config at its root, for both members.
    write(
      '.dart_tool/package_config.json',
      packageConfig({'app': 'pkgs/app', 'core': 'pkgs/core'}),
    );
    // A package with its own config, nested in the workspace.
    write(
      'pkgs/app/example/.dart_tool/package_config.json',
      packageConfig({'example': '.', 'app': '..'}),
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('PackageResolver.resolve', () {
    const from = 'pkgs/app/lib/app.dart';

    test('resolves a package: URI through the nearest config above', () {
      expect(
        PackageResolver().resolve('package:core/src/a.dart', path(from)),
        path('pkgs/core/lib/src/a.dart'),
      );
    });

    test('prefers a nested package own config', () {
      expect(
        PackageResolver().resolve(
          'package:example/e.dart',
          path('pkgs/app/example/bin/main.dart'),
        ),
        path('pkgs/app/example/lib/e.dart'),
      );
    });

    test('a package the config does not list is unknown', () {
      expect(
        PackageResolver().resolve('package:mystery/a.dart', path(from)),
        unknownPackage,
      );
    });

    test('without any config, every package is unknown', () {
      final outside = Directory.systemTemp.createTempSync('ciach_no_config_');
      addTearDown(() => outside.deleteSync(recursive: true));
      expect(
        PackageResolver().resolve(
          'package:app/app.dart',
          p.join(outside.path, 'lib', 'a.dart'),
        ),
        unknownPackage,
      );
    });
  });
}
