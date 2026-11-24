/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = .systemTemp.createTempSync('ciach_project_files_test_');
  });

  tearDown(() {
    root.deleteSync(recursive: true);
  });

  void write(String relativePath) =>
      File(p.join(root.path, p.joinAll(p.posix.split(relativePath))))
        ..createSync(recursive: true)
        ..writeAsStringSync('');

  test(
    'gives each Dart file to the innermost package, and lists the packages that have none',
    () {
      [
        'pubspec.yaml',
        'lib/app.dart',
        'packages/plugin/pubspec.yaml',
        'packages/plugin/lib/plugin.dart',
        'packages/plugin/example/pubspec.yaml',
        'packages/plugin/example/lib/main.dart',
        'packages/plugin-tools/bin/tool.dart',
        'packages/empty/pubspec.yaml',
      ].forEach(write);
      final tree = scanPackageTree(root.path);
      final dirs = packageDirs(root.path, tree);

      expect(dirs, [
        '',
        'packages/empty',
        'packages/plugin',
        'packages/plugin/example',
      ]);
      expect(
        {
          for (final MapEntry(key: dir, value: files) in dartFilesByPackage(
            root.path,
            dirs,
            tree,
          ).entries)
            dir: {for (final file in files) p.relative(file, from: root.path)},
        },
        {
          '': {'lib/app.dart', 'packages/plugin-tools/bin/tool.dart'},
          'packages/plugin': {'packages/plugin/lib/plugin.dart'},
          'packages/plugin/example': {'packages/plugin/example/lib/main.dart'},
        },
      );
    },
  );
}
