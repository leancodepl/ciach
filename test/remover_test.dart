import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ciach_remover_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [content] to `<tempDir>/lib.dart`, removes [decls] from it, and
  /// returns the resulting content.
  String applyRemoval(String content, List<UnusedDeclaration> decls) {
    File(p.join(tempDir.path, 'lib.dart')).writeAsStringSync(content);
    removeDeclarations(decls, tempDir.path);
    return File(p.join(tempDir.path, 'lib.dart')).readAsStringSync();
  }

  UnusedDeclaration decl({
    required int startLine,
    required int startColumn,
    required int endLine,
    required int endColumn,
    SymbolKind kind = .function,
    bool isEnumValue = false,
  }) => .new(
    name: 'x',
    kind: kind,
    filePath: 'lib.dart',
    line: startLine + 1,
    column: startColumn + 1,
    isPrivate: false,
    isEnumValue: isEnumValue,
    range: (
      startLine: startLine,
      startColumn: startColumn,
      endLine: endLine,
      endColumn: endColumn,
    ),
  );

  test('removes a top-level function along with its doc comment', () {
    const source = '''
void kept() {}

/// Never referenced.
void danglingFunction() {}

void alsoKept() {}
''';
    // `void danglingFunction() {}` is line index 3, columns 0..26.
    final result = applyRemoval(source, [
      decl(startLine: 3, startColumn: 0, endLine: 3, endColumn: 26),
    ]);
    expect(result, isNot(contains('danglingFunction')));
    expect(result, isNot(contains('Never referenced')));
    expect(result, contains('void kept() {}'));
    expect(result, contains('void alsoKept() {}'));
  });

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
      ),
    ]);
    expect(result, isNot(contains('_unusedField')));
    expect(result, isNot(contains('final int')));
    expect(result, isNot(contains('Doc.')));
    expect(result, contains('class C {'));
    expect(result, contains('void method() {}'));
    _expectBalanced(result);
  });

  group('multi-declarator statement `int a = 1, b = 2, c = 3;`', () {
    const source = 'int a = 1, b = 2, c = 3;\n';
    // Columns of each declarator's `name = value` span within the line.
    const aRange = (start: 4, end: 9);
    const bRange = (start: 11, end: 16);
    const cRange = (start: 18, end: 23);

    UnusedDeclaration declaratorAt(({int start, int end}) range) => decl(
      startLine: 0,
      startColumn: range.start,
      endLine: 0,
      endColumn: range.end,
      kind: .variable,
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
    // Range covers `_cache = {}` only, as the analysis server reports it.
    final start = source.indexOf('_cache');
    final end = source.indexOf(';');
    final result = applyRemoval(source, [
      decl(
        startLine: 0,
        startColumn: start,
        endLine: 0,
        endColumn: end,
        kind: .field,
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
      _expectBalanced(result);
    });
  });

  test('collapses a fully-unused class into a single removal', () {
    const lines = [
      'class Kept {}',
      '',
      '/// Never referenced.',
      'class UnusedClass {',
      '  /// Never referenced.',
      '  void orphanMethod() {}',
      '}',
      '',
      'class AlsoKept {}',
      '',
    ];
    final source = lines.join('\n');

    final result = applyRemoval(source, [
      // Ranges start at the declaration's keyword (`class`/`void`), not at
      // the name — matching how the analysis server reports whole-node
      // kinds (only `field`/`variable`/`constant` exclude their prefix).
      decl(
        startLine: 3,
        startColumn: 0,
        endLine: 6,
        endColumn: 1,
        kind: .class$,
      ),
      decl(
        startLine: 5,
        startColumn: 2,
        endLine: 5,
        endColumn: 2 + 'void orphanMethod() {}'.length,
        kind: .method,
      ),
    ]);
    expect(result, isNot(contains('UnusedClass')));
    expect(result, isNot(contains('orphanMethod')));
    expect(result, contains('class Kept {}'));
    expect(result, contains('class AlsoKept {}'));
    _expectBalanced(result);
  });

  test('removing nothing leaves the file untouched', () {
    const source = 'void kept() {}\n';
    expect(applyRemoval(source, const []), source);
  });
}

/// A cheap brace-balance check so a regression that mangles a removal shows
/// up in these fast unit tests, without needing the full analyzer.
void _expectBalanced(String source) {
  var depth = 0;
  for (final ch in source.split('')) {
    if (ch == '{') {
      depth++;
    }
    if (ch == '}') {
      depth--;
    }
    expect(depth, greaterThanOrEqualTo(0), reason: 'unbalanced braces');
  }
  expect(depth, 0, reason: 'unbalanced braces');
}
