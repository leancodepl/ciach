/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

/// A file whose lines end with `\r\n`.
void main() {
  late Directory tmp;
  late String packagePath;

  setUp(() {
    tmp = .systemTemp.createTempSync('ciach_line_endings_');
    packagePath = p.join(tmp.path, 'pkg');
    File(p.join(packagePath, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: pkg\n');
    File(p.join(packagePath, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'pkg': '.'}));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  /// The lines of `lib/a.dart`, before and after `--remove`.
  const lines = [
    'void main() => used();',
    '',
    'void used() {}',
    '',
    '// ciach:ignore',
    'void kept() {}',
    '',
    '/// Not used.',
    'void dead() {}',
    '',
  ];
  // The blank line above the removed function stays, as with `\n`.
  const removed = [
    'void main() => used();',
    '',
    'void used() {}',
    '',
    '// ciach:ignore',
    'void kept() {}',
    '',
    '',
  ];

  test(
    r'with `\r\n` line endings, a finding has the line and column of its name, a marker keeps the next line, and `--remove` deletes the finding',
    () async {
      final file = File(p.join(packagePath, 'lib', 'a.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync(lines.join('\r\n'));

      final result = await Ciach(.new(rootPath: packagePath)).run();
      removeDeclarations(result.unused, packagePath);

      expect(
        [
          for (final finding in result.unused)
            (finding.name, finding.line, finding.column),
        ],
        [('dead', 9, 6)],
      );
      expect(file.readAsStringSync(), removed.join('\r\n'));
    },
  );
}
