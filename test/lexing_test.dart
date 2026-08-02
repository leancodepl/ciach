/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/lexing.dart';
import 'package:test/test.dart';

void main() {
  group('stripComments', () {
    test('blanks a // line comment but keeps its length and newline', () {
      const src = 'void f() {} // mentions @override\nvoid g() {}';
      final out = stripComments(src);
      expect(out, isNot(contains('@override')));
      expect(out, contains('void f() {}'));
      expect(out, contains('void g() {}'));
      // Offsets are preserved: same length, same line breaks.
      expect(out.length, src.length);
      expect('\n'.allMatches(out).length, '\n'.allMatches(src).length);
    });

    test('blanks a /// doc comment', () {
      const src = '/// This used to be an @override hook.\nvoid f() {}';
      final out = stripComments(src);
      expect(out, isNot(contains('@override')));
      expect(out, contains('void f() {}'));
    });

    test('blanks a nested, multi-line /* */ block comment', () {
      const src = '/* outer @override /* inner vm:entry-point */ still */\nx';
      final out = stripComments(src);
      expect(out, isNot(contains('@override')));
      expect(out, isNot(contains('vm:entry-point')));
      expect(out.trimRight(), endsWith('x'));
      expect(out.length, src.length);
    });

    test('keeps a real @override annotation', () {
      const src = '@override\nString sound() => "";';
      expect(stripComments(src), contains('@override'));
    });

    test('keeps vm:entry-point inside a @pragma string literal', () {
      const src = "@pragma('vm:entry-point')\nvoid f() {}";
      expect(stripComments(src), contains('vm:entry-point'));
    });

    test('blanks vm:entry-point when it only appears in a comment', () {
      const src = '// was a vm:entry-point\nvoid f() {}';
      expect(stripComments(src), isNot(contains('vm:entry-point')));
    });

    test(
      'keeps a real @freezed but blanks one only mentioned in a comment',
      () {
        expect(stripComments('@freezed\nclass A {}'), contains('@freezed'));
        expect(
          stripComments('/// like @freezed\nclass A {}'),
          isNot(contains('@freezed')),
        );
      },
    );

    test('does not treat // inside a string literal as a comment', () {
      const src = "final s = 'a // @override b';";
      expect(stripComments(src), contains('@override'));
    });

    test('leaves a raw string intact', () {
      const src = r"final p = r'C:\x // @override';";
      expect(stripComments(src), contains('@override'));
    });

    test('leaves an interpolated string intact', () {
      const src = r"final s = '$x // @override';";
      expect(stripComments(src), contains('@override'));
    });
  });
}
