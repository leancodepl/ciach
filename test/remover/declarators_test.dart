import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:test/test.dart';

import '../support/removal.dart';

/// `--remove` on `field`/`variable`/`constant` declarators, which share a
/// statement — and a `final`/`const`/type prefix — with their siblings.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_remover_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String applyRemoval(String content, List<UnusedDeclaration> decls) =>
      removeFrom(tempDir, content, decls);

  test('removes a sole-declarator field including its type prefix and `;`', () {
    const source = '''
class C {
  /// Doc.
  final int _unusedField = 0;

  void method() {}
}
''';
    // The field's own range covers only `_unusedField = 0` — no
    // `final int ` prefix and no trailing `;` — matching what the
    // analysis server reports for a `VariableDeclaration`.
    const fieldLine = '  final int _unusedField = 0;';
    final start = fieldLine.indexOf('_unusedField');
    final end = fieldLine.indexOf(' = 0') + ' = 0'.length;
    final result = applyRemoval(source, [
      decl(
        startLine: 2,
        startColumn: start,
        endLine: 2,
        endColumn: end,
        kind: .field,
        docLine: 1,
        docColumn: 2,
      ),
    ]);
    expect(result, isNot(contains('_unusedField')));
    expect(result, isNot(contains('final int')));
    expect(result, isNot(contains('Doc.')));
    expect(result, contains('class C {'));
    expect(result, contains('void method() {}'));
    expectBalanced(result);
  });

  group('multi-declarator statement `int a = 1, b = 2, c = 3;`', () {
    const source = 'int a = 1, b = 2, c = 3;\n';
    // Columns of each declarator's `name = value` span within the line.
    const aRange = (start: 4, end: 9);
    const bRange = (start: 11, end: 16);
    const cRange = (start: 18, end: 23);

    // The first declarator's full range starts at `int`; the others at their name.
    UnusedDeclaration declaratorAt(({int start, int end}) range) => decl(
      startLine: 0,
      startColumn: range.start,
      endLine: 0,
      endColumn: range.end,
      kind: .variable,
      docLine: range == aRange ? 0 : null,
    );

    test('drops the trailing comma when removing the first declarator', () {
      final result = applyRemoval(source, [declaratorAt(aRange)]);
      // The shared `int ` prefix is left for the surviving declarators; the
      // resulting double space is cosmetic and `dart format` cleans it up.
      expect(result.trim(), 'int  b = 2, c = 3;');
    });

    test('drops one neighboring comma when removing a middle declarator', () {
      final result = applyRemoval(source, [declaratorAt(bRange)]);
      expect(result.trim(), 'int a = 1, c = 3;');
    });

    test('drops the leading comma but keeps `;` when removing the last '
        'declarator', () {
      final result = applyRemoval(source, [declaratorAt(cRange)]);
      expect(result.trim(), 'int a = 1, b = 2;');
    });

    test('removes the whole statement when every declarator is unused', () {
      final result = applyRemoval(source, [
        declaratorAt(aRange),
        declaratorAt(bRange),
        declaratorAt(cRange),
      ]);
      expect(result.trim(), isEmpty);
    });
  });

  test('does not mistake a comma inside a generic type for a declarator '
      'separator', () {
    const source = 'Map<String, int> _cache = {};\n';
    // The range covers `_cache = {}` only, as the analysis server reports it.
    final start = source.indexOf('_cache');
    final end = source.indexOf(';');
    final result = applyRemoval(source, [
      decl(
        startLine: 0,
        startColumn: start,
        endLine: 0,
        endColumn: end,
        kind: .field,
        docLine: 0,
      ),
    ]);
    expect(result.trim(), isEmpty);
  });

  test("leaves a declarator alone when a top-level separator can't be found "
      '(unresolvable shape)', () {
    // A synthetic, deliberately-unbalanced range: the forward scan for a
    // terminating `,`/`;` hits an unmatched `)` first and bails out rather
    // than guess.
    const source = 'int a = 1);\n';
    final result = applyRemoval(source, [
      decl(
        startLine: 0,
        startColumn: 4,
        endLine: 0,
        endColumn: 9,
        kind: .variable,
      ),
    ]);
    expect(result, source);
  });

  test('a declarator reported and coupled at once is removed once', () {
    // Each of the two dead members couples its own declarator of one
    // statement, and the second declarator is also a finding in its own right.
    // The same declarator arriving twice must not confuse the span arithmetic.
    const source = '''
class Pair {
  final int left = 1, right = 2;
}
''';
    // `left = 1` is line 1, cols 12..20; `right = 2` cols 22..31.
    const right = UnusedDeclaration(
      name: 'right',
      kind: .field,
      filePath: 'lib.dart',
      line: 2,
      column: 23,
      isPrivate: false,
      range: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
      fullRange: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
      coupledRemovals: [
        // The same declarator, coupled to the member it overrides.
        (
          filePath: 'lib.dart',
          kind: .field,
          range: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
          fullRange: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
        ),
        // And the statement's other declarator.
        (
          filePath: 'lib.dart',
          kind: .field,
          range: (startLine: 1, startColumn: 12, endLine: 1, endColumn: 20),
          fullRange: (startLine: 1, startColumn: 2, endLine: 1, endColumn: 20),
        ),
      ],
    );
    final result = applyRemoval(source, [right]);
    expect(result, isNot(contains('left')));
    expect(result, isNot(contains('right')));
    expect(result, contains('class Pair {'));
    expectBalanced(result);
  });

  test(
    'a coupled declarator is taken out of a statement that keeps the rest',
    () {
      // The implementing declarator shares its statement with a live one: the
      // statement stays, one declarator goes.
      const source = '''
abstract class Halved {
  int get dead;
}

class Mixed implements Halved {
  final int dead = 1, live = 2;
}
''';
      // `int get dead;` is line 1, cols 2..15; `dead = 1` is line 5, cols 12..20,
      // and the statement it starts begins at col 2.
      const member = UnusedDeclaration(
        name: 'dead',
        kind: .property,
        filePath: 'lib.dart',
        line: 2,
        column: 11,
        isPrivate: false,
        range: (startLine: 1, startColumn: 2, endLine: 1, endColumn: 15),
        coupledRemovals: [
          (
            filePath: 'lib.dart',
            kind: .field,
            range: (startLine: 5, startColumn: 12, endLine: 5, endColumn: 20),
            fullRange: (
              startLine: 5,
              startColumn: 2,
              endLine: 5,
              endColumn: 20,
            ),
          ),
        ],
      );
      final result = applyRemoval(source, [member]);
      expect(result, isNot(contains('dead')));
      expect(result, contains('live = 2;'));
      expect(result, contains('class Mixed implements Halved {'));
      expectBalanced(result);
    },
  );
}
