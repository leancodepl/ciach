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

/// An exported package whose `lib/src/helper.dart` type no other package can
/// reach, so the uses of its members are looked up where the type is named.
/// The first use of `Helper.run` is in dead code, the second is live. The only
/// use of `Helper.stop` is in dead code. `Helper.close` is used in dead code
/// and live in `bin/main.dart`, which doesn't name `Helper`.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_probed_members_');
    write('.dart_tool/package_config.json', packageConfig({'demo': '.'}));
    write('pubspec.yaml', '''
name: demo
environment: {sdk: ^3.10.0}
''');
    write('lib/demo.dart', '''
import 'src/helper.dart';

void _dead() => Helper()
  ..run()
  ..stop()
  ..close();

void live() => Helper().run();
''');
    write('lib/src/helper.dart', '''
class Helper {
  void run() {}

  void stop() {}

  void close() {}
}
''');
    write('bin/make.dart', '''
import 'package:demo/src/helper.dart';

Helper make() => Helper();
''');
    write('bin/main.dart', '''
import 'make.dart';

void main() => make().close();
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test(
    'members used in dead code and live elsewhere are used, with no '
    'recovered reference, and a member used only in dead code is unused',
    () async {
      final result = await Ciach(
        .new(rootPath: root.path, exportedPackages: const ['**']),
      ).run();
      expect(result.unused.map((d) => d.qualifiedName), [
        '_dead',
        'Helper.stop',
      ]);
      expect(result.recoveredReferences, isEmpty);
    },
  );

  test(
    "a member used in dead code and live only in an excluded file that doesn't name its type is used",
    () async {
      final result = await Ciach(
        .new(
          rootPath: root.path,
          exportedPackages: const ['**'],
          excludeGlobs: const ['bin/**'],
        ),
      ).run();
      expect(result.unused.map((d) => d.qualifiedName), [
        '_dead',
        'Helper.stop',
      ]);
    },
  );
}
