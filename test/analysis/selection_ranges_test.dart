/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';
import '../support/resolved_files.dart';

/// The syntax nodes that `selectionRangeIn` lists, read through
/// `ResolvedFiles.selectionRangeAt`.
void main() {
  late Directory tempDir;
  late ResolvedFiles files;
  var written = 0;

  setUpAll(() {
    tempDir = .systemTemp.createTempSync('ciach_selection_ranges_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'app': '.'}));
    files = resolvedFilesUnder(tempDir.path);
  });

  tearDownAll(() async {
    await files.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// The text of each node that holds the first [marker] in [source],
  /// written to a new file, innermost first.
  List<String> nodesAt(String source, String marker) {
    final path = p.join(tempDir.path, 'lib', 'file${written++}.dart');
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
    final lines = source.split('\n');
    final offset = source.indexOf(marker);
    final line = '\n'.allMatches(source.substring(0, offset)).length;
    int offsetOf(Position position) =>
        lines
            .take(position.line)
            .fold(0, (sum, line) => sum + line.length + 1) +
        position.character;
    return [
      for (
        var node = files.selectionRangeAt(
          path,
          .new(
            line: line,
            character: offset - (source.lastIndexOf('\n', offset - 1) + 1),
          ),
        );
        node != null;
        node = node.parent
      )
        source.substring(offsetOf(node.range.start), offsetOf(node.range.end)),
    ];
  }

  test(
    'lists each node that holds the position once, innermost first, without the name of a class header',
    () {
      expect(
        nodesAt('''
class A<T> {
  int get x => 1;
}
''', 'A<T>'),
        [
          '''
class A<T> {
  int get x => 1;
}''',
        ],
      );
    },
  );

  test('lists the body of a class and of a function', () {
    expect(
      nodesAt('''
class A {
  int get x => 1;
}
''', '1;'),
      [
        '1',
        '=> 1;',
        'int get x => 1;',
        '''
{
  int get x => 1;
}''',
        '''
class A {
  int get x => 1;
}''',
      ],
    );
  });

  test('lists a parameter without its default value before it', () {
    expect(nodesAt('void f({int x = 1}) {}\n', 'x ='), [
      'int x',
      'int x = 1',
      '({int x = 1})',
      '({int x = 1}) {}',
      'void f({int x = 1}) {}',
    ]);
  });

  test('lists the name of a named argument, and its name with the colon', () {
    expect(nodesAt('void f({int? x}) => f(x: 1);\n', 'x: 1'), [
      'x',
      'x:',
      'x: 1',
      '(x: 1)',
      'f(x: 1)',
      '=> f(x: 1);',
      '({int? x}) => f(x: 1);',
      'void f({int? x}) => f(x: 1);',
    ]);
  });

  test('is empty where no node is', () {
    expect(
      nodesAt('''
void f() {}

void g() {}
''', '\nvoid g'),
      [''],
    );
  });
}
