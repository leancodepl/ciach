@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// The server outlines `group(…)` and `test(…)` calls; they declare nothing,
/// so they get no reference query.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() {
    root = .systemTemp.createTempSync('ciach_unit_test_calls_');
    write('pubspec.yaml', '''
name: pkg
environment:
  sdk: ^3.10.0
''');
    write('.dart_tool/package_config.json', packageConfig({'pkg': '.'}));
    // The server takes a function from a library named `*test.dart` for a
    // test framework's.
    write('lib/test.dart', '''
void group(String description, void Function() body) => body();

void test(String description, void Function() body) => body();
''');
    write('test/a_test.dart', '''
import 'package:pkg/test.dart';

void main() {
  group('a group', () {
    test('a test', () {});
  });
}

void _unused() {}
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('checks the declarations but not the group and test calls', () async {
    final result = await Ciach(.new(rootPath: root.path)).run();

    expect(result.unused.map((d) => d.name), ['_unused']);
    expect(result.declarationsChecked, 3);
  });
}
