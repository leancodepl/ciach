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
/// The first use of `Helper.run` is in dead code, the second is live.
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

void _dead() => Helper().run();

void live() => Helper().run();
''');
    write('lib/src/helper.dart', '''
class Helper {
  void run() {}
}
''');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  test('a member whose first use found is dead is used, with no recovered '
      'reference', () async {
    final result = await Ciach(
      .new(rootPath: root.path, exportedPackages: const ['**']),
    ).run();
    expect(result.unused.map((d) => d.qualifiedName), ['_dead']);
    expect(result.recoveredReferences, isEmpty);
  });
}
