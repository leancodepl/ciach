/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

/// An exported package with an internal `Helper` type in two variants of a
/// conditional import. The server resolves every use to `helper_io.dart`.
/// `Helper.close` is used in dead code and live only in the excluded
/// `bin/main.dart`, which doesn't name `Helper`.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_probed_variants_');
    write('.dart_tool/package_config.json', packageConfig({'demo': '.'}));
    write('pubspec.yaml', '''
name: demo
environment: {sdk: ^3.10.0}
''');
    write('lib/demo.dart', '''
import 'src/helper_io.dart' if (dart.library.js_interop) 'src/helper_web.dart';

void _dead() => Helper().close();
''');
    for (final variant in ['io', 'web']) {
      write('lib/src/helper_$variant.dart', '''
class Helper {
  void close() {}
}
''');
    }
    write('bin/make.dart', '''
import 'package:demo/src/helper_io.dart'
    if (dart.library.js_interop) 'package:demo/src/helper_web.dart';

Helper make() => Helper();
''');
    write('bin/main.dart', '''
import 'make.dart';

void main() => make().close();
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test('a member of both variants used in dead code and live only in an '
      'excluded file is used in both', () async {
    final result = await Ciach(
      .new(
        rootPath: root.path,
        exportedPackages: const ['**'],
        excludeGlobs: const ['bin/**'],
      ),
    ).run();
    expect(result.unused.map((d) => (d.filePath, d.qualifiedName)), [
      ('lib/demo.dart', '_dead'),
    ]);
  });
}
