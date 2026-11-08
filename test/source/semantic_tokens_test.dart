/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:test/test.dart';

void main() {
  SemanticToken token(int line, int character, String text, String type) =>
      .new(
        line: line,
        character: character,
        length: text.length,
        type: type,
        modifiers: const {},
        text: text,
      );

  group('lookups', () {
    // The tokens of `/// Doc for [Foo].`, `@override` and `void f() {}`.
    final tokens = [
      token(0, 0, '/// Doc for [', 'comment'),
      token(0, 13, 'Foo', 'class'),
      token(0, 16, '].', 'comment'),
      token(1, 0, '@', 'annotation'),
      token(1, 1, 'override', 'property'),
      token(2, 0, 'void', 'keyword'),
      token(2, 5, 'f', 'function'),
    ];

    test("find a line's first token and a token by its start", () {
      expect(
        (
          tokens.firstOnLine(0)?.text,
          tokens.firstOnLine(1)?.text,
          tokens.firstOnLine(7),
          tokens.startingAt(const .new(line: 0, character: 13))?.text,
          tokens.startingAt(const .new(line: 0, character: 14)),
        ),
        ('/// Doc for [', '@', null, 'Foo', null),
      );
    });

    test('find the tokens that start between two positions', () {
      expect(
        tokens
            .between(
              const .new(line: 0, character: 0),
              const .new(line: 2, character: 0),
            )
            .map((t) => t.text),
        ['/// Doc for [', 'Foo', '].', '@', 'override'],
      );
    });
  });

  group('SemanticToken.stringValue', () {
    test('is the text between the quotes of a plain string literal', () {
      expect(
        [
          "'vm:entry-point'",
          '"vm:entry-point"',
          "r'vm:entry-point'",
          "'''vm:entry-point'''",
          '"""vm:entry-point"""',
        ].map((text) => token(0, 0, text, 'string').stringValue),
        everyElement('vm:entry-point'),
      );
    });

    test(
      'is `null` for a string with an escape or an interpolation, and for another token',
      () {
        expect(
          [
            token(0, 0, r"'vm:entry\-point'", 'string'),
            token(0, 0, r"'vm:$point'", 'string'),
            token(0, 0, '\'vm:entry-point"', 'string'),
            token(0, 0, 'entryPoint', 'variable'),
          ].map((token) => token.stringValue),
          everyElement(isNull),
        );
      },
    );
  });
}
