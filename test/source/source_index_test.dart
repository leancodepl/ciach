/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:test/test.dart';

import '../support/fake_syntax.dart';

void main() {
  test(
    'the leading metadata of a declaration is its tokens before the code',
    () {
      const path = '/project/lib/a.dart';
      SemanticToken token(int line, int character, String text) => .new(
        line: line,
        character: character,
        length: text.length,
        type: 'comment',
        modifiers: const {},
        text: text,
      );
      // `/// Doc.`, `@override` and `void f() {}`.
      final syntax = FakeSyntax()
        ..tokens[path] = [
          token(0, 0, '/// Doc.'),
          token(1, 0, '@'),
          token(1, 1, 'override'),
          token(2, 0, 'void'),
          token(2, 5, 'f'),
        ];
      const outline = Outline(
        element: .new(kind: .function, name: 'f'),
        range: .new(
          start: .new(line: 0, character: 0),
          end: .new(line: 2, character: 11),
        ),
        codeRange: .new(
          start: .new(line: 2, character: 0),
          end: .new(line: 2, character: 11),
        ),
        children: [],
      );

      expect(
        SourceIndex(syntax).leadingMetadata(path, outline).map((t) => t.text),
        ['/// Doc.', '@', 'override'],
      );
    },
  );
}
