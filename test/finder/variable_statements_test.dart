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

void main() {
  test(
    'an annotation on a statement that declares several variables applies to each of them',
    () async {
      final root = Directory.systemTemp.createTempSync('ciach_statements_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String contents) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
      write('.dart_tool/package_config.json', packageConfig({'vars': '.'}));
      write('pubspec.yaml', '''
name: vars
environment: {sdk: ^3.13.0}
''');
      write('lib/vars.dart', '''
@pragma('vm:entry-point')
int first = 0, second = 0;

int reported = 0, alsoReported = 0;

class Holder {
  @pragma('vm:entry-point')
  static int firstField = 0, secondField = 0;
}

void main() => print(Holder());
''');

      final result = await Ciach(.new(rootPath: root.path)).run();

      expect(result.unused.map((d) => d.qualifiedName), {
        'reported',
        'alsoReported',
      });
    },
  );
}
