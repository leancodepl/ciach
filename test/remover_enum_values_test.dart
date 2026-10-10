import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:test/test.dart';

import 'support/removal.dart';

/// `--remove` on enum values: the commas, `;` and members around them.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_enum_values_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String applyRemoval(String content, List<UnusedDeclaration> decls) =>
      removeFrom(tempDir, content, decls);

  group('enum values', () {
    test('removes a middle value along with its trailing comma', () {
      const source = '''
enum Direction {
  north,
  south,
  east,
}
''';
      final result = applyRemoval(source, [
        decl(
          startLine: 2,
          startColumn: 2,
          endLine: 2,
          endColumn: 2 + 'south'.length,
          isEnumValue: true,
        ),
      ]);
      expect(result, isNot(contains('south')));
      expect(result, contains('north,'));
      expect(result, contains('east,'));
      expect(result, isNot(contains(',,')));
    });

    test('removes the last value when there is no trailing comma', () {
      const source = '''
enum Direction {
  north,
  south
}
''';
      final result = applyRemoval(source, [
        decl(
          startLine: 2,
          startColumn: 2,
          endLine: 2,
          endColumn: 2 + 'south'.length,
          isEnumValue: true,
        ),
      ]);
      expect(result, isNot(contains('south')));
      expect(result, contains('north'));
      expect(result, isNot(contains('north,,')));
      expectBalanced(result);
    });

    group('compact single-line `enum Size { small, medium, large }`', () {
      const source = 'enum Size { small, medium, large }\n';

      UnusedDeclaration valueNamed(String name) {
        final start = source.indexOf(name);
        return decl(
          startLine: 0,
          startColumn: start,
          endLine: 0,
          endColumn: start + name.length,
          isEnumValue: true,
        );
      }

      test('removes a middle value without corrupting the declaration', () {
        final result = applyRemoval(source, [valueNamed('medium')]);
        expect(result, isNot(contains('medium')));
        expect(result, contains('enum Size {'));
        expect(result, contains('small'));
        expect(result, contains('large'));
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });

      test('removes the last value without corrupting the declaration', () {
        final result = applyRemoval(source, [valueNamed('large')]);
        expect(result, isNot(contains('large')));
        expect(result, contains('enum Size {'));
        expect(result, contains('small'));
        expect(result, contains('medium'));
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });
    });

    group('compact single-line, removing multiple values in one pass', () {
      const source = 'enum E { a, b, c, d }\n';

      UnusedDeclaration valueNamed(String name) {
        final start = source.indexOf(name);
        return decl(
          startLine: 0,
          startColumn: start,
          endLine: 0,
          endColumn: start + name.length,
          isEnumValue: true,
        );
      }

      test('removes two non-adjacent middle values', () {
        final result = applyRemoval(source, [valueNamed('b'), valueNamed('d')]);
        expect(result, contains('enum E {'));
        expect(result, contains('a'));
        expect(result, contains('c'));
        expect(result, isNot(contains('b')));
        expect(result, isNot(contains('d')));
        expect(result, isNot(contains(',,')));
        expect(result.trim(), 'enum E { a, c }');
        expectBalanced(result);
      });

      test('removes two adjacent middle values', () {
        final result = applyRemoval(source, [valueNamed('b'), valueNamed('c')]);
        expect(result, contains('enum E {'));
        expect(result, contains('a'));
        expect(result, contains('d'));
        expect(result, isNot(contains('b')));
        expect(result, isNot(contains('c')));
        expect(result, isNot(contains(',,')));
        expect(result.trim(), 'enum E { a, d }');
        expectBalanced(result);
      });

      test('removes a trailing run, leaving no dangling separator comma', () {
        // Regression: removing the last values used to leave a dangling `,`.
        final result = applyRemoval(source, [valueNamed('c'), valueNamed('d')]);
        expect(result, contains('enum E {'));
        expect(result, contains('a'));
        expect(result, contains('b'));
        expect(result, isNot(contains('c')));
        expect(result, isNot(contains('d')));
        expect(result, isNot(contains(',,')));
        expect(result.trim(), 'enum E { a, b }');
        expectBalanced(result);
      });

      test('removes a leading run, keeping the surviving values', () {
        final result = applyRemoval(source, [valueNamed('a'), valueNamed('b')]);
        expect(result, contains('enum E {'));
        expect(result, contains('c'));
        expect(result, contains('d'));
        expect(result, isNot(contains('a')));
        expect(result, isNot(contains('b')));
        expect(result, isNot(contains(',,')));
        expect(result.trim(), 'enum E { c, d }');
        expectBalanced(result);
      });
    });

    group('compact single-line enum with a leading `///` doc comment', () {
      // The line above the values is the enum type's doc comment — it must
      // never be swept into a value's removal span.
      const source =
          '/// Doc comment on the enum type.\n'
          'enum Accuracy { best, high, medium }\n';

      UnusedDeclaration valueNamed(String name) {
        final start = source.indexOf(name);
        final line = '\n'.allMatches(source.substring(0, start)).length;
        final column = start - (source.lastIndexOf('\n', start - 1) + 1);
        return decl(
          startLine: line,
          startColumn: column,
          endLine: line,
          endColumn: column + name.length,
          isEnumValue: true,
        );
      }

      test(
        'removing one value keeps the doc comment, header and kept values',
        () {
          final result = applyRemoval(source, [valueNamed('high')]);
          expect(result, contains('/// Doc comment on the enum type.'));
          expect(result, contains('enum Accuracy {'));
          expect(result, contains('best'));
          expect(result, contains('medium'));
          expect(result, isNot(contains('high')));
          expect(result, isNot(contains(',,')));
          expectBalanced(result);
        },
      );

      test('removing multiple values keeps the doc comment and header', () {
        final result = applyRemoval(source, [
          valueNamed('high'),
          valueNamed('medium'),
        ]);
        expect(result, contains('/// Doc comment on the enum type.'));
        expect(result, contains('enum Accuracy { best }'));
        expect(result, isNot(contains('high')));
        expect(result, isNot(contains('medium')));
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });
    });

    group('compact single-line enum with a `//` line and annotation above', () {
      // The comment and annotation belong to the enum type, not a value, and
      // must survive value removal.
      const source =
          '// Ordered from least to most precise.\n'
          '@immutable\n'
          'enum Level { low, mid, top }\n';

      UnusedDeclaration valueNamed(String name) {
        final start = source.indexOf(' $name') + 1;
        final line = '\n'.allMatches(source.substring(0, start)).length;
        final column = start - (source.lastIndexOf('\n', start - 1) + 1);
        return decl(
          startLine: line,
          startColumn: column,
          endLine: line,
          endColumn: column + name.length,
          isEnumValue: true,
        );
      }

      test('removing values keeps the comment, annotation and header', () {
        final result = applyRemoval(source, [
          valueNamed('mid'),
          valueNamed('top'),
        ]);
        expect(result, contains('// Ordered from least to most precise.'));
        expect(result, contains('@immutable'));
        expect(result, contains('enum Level { low }'));
        expect(result, isNot(contains('mid')));
        expect(result, isNot(contains('top')));
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });
    });

    group('removing every value', () {
      // NOTE: an enum with no values is invalid Dart, so removing *all* of an
      // enum's values would leave `enum Foo {}`, which won't compile. The
      // safety net that refuses this whole-enum removal lives elsewhere (the
      // `removalBlocked` guard on the empty-enum branch, PR #10), not in the
      // remover's span logic. These tests only pin down that this branch's
      // span math stays clean when it is handed every value: the values and
      // their separators come out with no leftover names, no dangling/`,,`
      // comma, and balanced braces — it just collapses to an empty body.

      test('multi-line enum collapses to an empty body', () {
        const source = '''
enum Direction {
  north,
  south,
  east,
}
''';
        UnusedDeclaration valueNamed(String name) {
          final start = source.indexOf('  $name') + 2;
          final line = '\n'.allMatches(source.substring(0, start)).length;
          final column = start - (source.lastIndexOf('\n', start - 1) + 1);
          return decl(
            startLine: line,
            startColumn: column,
            endLine: line,
            endColumn: column + name.length,
            isEnumValue: true,
          );
        }

        final result = applyRemoval(source, [
          valueNamed('north'),
          valueNamed('south'),
          valueNamed('east'),
        ]);
        expect(result, isNot(contains('north')));
        expect(result, isNot(contains('south')));
        expect(result, isNot(contains('east')));
        expect(result, isNot(contains(',')));
        expect(result.trim(), 'enum Direction {\n}');
        expectBalanced(result);
      });

      test('compact single-line enum collapses to an empty body', () {
        const source = 'enum Empty { a, b, c }\n';
        UnusedDeclaration valueNamed(String name) {
          final start = source.indexOf(' $name') + 1;
          return decl(
            startLine: 0,
            startColumn: start,
            endLine: 0,
            endColumn: start + name.length,
            isEnumValue: true,
          );
        }

        final result = applyRemoval(source, [
          valueNamed('a'),
          valueNamed('b'),
          valueNamed('c'),
        ]);
        expect(result, isNot(contains(',')));
        expect(result, isNot(contains(',,')));
        // Clean span math: header and braces survive, body is emptied.
        expect(result.trim(), 'enum Empty {  }');
        expectBalanced(result);
      });
    });

    group('enhanced enum (values, then `;` and other members)', () {
      // Removing the last *value* must drop the value and its separator comma
      // but leave the `;` that terminates the value list and every trailing
      // member (constructors/fields/methods) untouched.

      test('multi-line: removing the last value keeps the `;` and members', () {
        const source = '''
enum E {
  a,
  b;

  const E();
  int get v => 0;
}
''';
        // `b` is the last value, on line index 2, columns 2..3.
        final result = applyRemoval(source, [
          decl(
            startLine: 2,
            startColumn: 2,
            endLine: 2,
            endColumn: 3,
            isEnumValue: true,
          ),
        ]);
        expect(result, isNot(contains('  b')));
        // The surviving last value now carries the list-terminating `;`.
        expect(result, contains('  a;'));
        expect(result, contains('const E();'));
        expect(result, contains('int get v => 0;'));
        expect(result, isNot(contains(',,')));
        expect(result, isNot(contains(', ;')));
        expectBalanced(result);
      });

      test('compact: removing the last value keeps the `;` and members', () {
        const source = 'enum E { a, b; final int x = 0; }\n';
        final start = source.indexOf(' b') + 1;
        final result = applyRemoval(source, [
          decl(
            startLine: 0,
            startColumn: start,
            endLine: 0,
            endColumn: start + 1,
            isEnumValue: true,
          ),
        ]);
        expect(result.trim(), 'enum E { a; final int x = 0; }');
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });

      test('multi-line: removing a middle value keeps the `;` and members', () {
        const source = '''
enum E {
  a,
  b,
  c;

  int get v => 0;
}
''';
        // `b` is a middle value, on line index 2, columns 2..3.
        final result = applyRemoval(source, [
          decl(
            startLine: 2,
            startColumn: 2,
            endLine: 2,
            endColumn: 3,
            isEnumValue: true,
          ),
        ]);
        expect(result, isNot(contains('  b')));
        expect(result, contains('  a,'));
        // `c` remains the last value and keeps terminating the list with `;`.
        expect(result, contains('  c;'));
        expect(result, contains('int get v => 0;'));
        expect(result, isNot(contains(',,')));
        expectBalanced(result);
      });
    });
  });
}
