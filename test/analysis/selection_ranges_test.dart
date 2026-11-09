/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/source/line_starts.dart';
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/test_package.dart';

/// The syntax nodes that `selectionRangeIn` lists, read through
/// `ResolvedFiles.selectionRangeAt`.
void main() {
  late TestPackage package;

  setUpAll(() => package = .new('selection_ranges'));

  tearDownAll(() => package.dispose());

  /// The text of each node that holds the first [marker] in [source],
  /// written to a new file, innermost first.
  List<String> nodesAt(String source, String marker) {
    final path = package.writeNew(source);
    return [
      for (
        var node = package.files.selectionRangeAt(
          path,
          positionIn(lineStartsOf(source), source.indexOf(marker)),
        );
        node != null;
        node = node.parent
      )
        textIn(source, node.range),
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
