/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/analysis/comments.dart';
import 'package:ciach/src/analysis/dart_text.dart';
import 'package:test/test.dart';

void main() {
  group('lineCommentsIn', () {
    /// The text of each `//` comment that [lineCommentsIn] finds in
    /// [content].
    List<String> commentsIn(String content) => [
      for (final (offset: _, :text) in lineCommentsIn(content)) text,
    ];

    test('finds a // comment and its offset, up to the end of its line', () {
      expect(lineCommentsIn('void f() {} // why\nvoid g() {}'), [
        (offset: 12, text: '// why'),
      ]);
    });

    test('finds a // comment that runs to the end of the file', () {
      expect(commentsIn('void f() {}\n// tail'), ['// tail']);
    });

    test('finds a /// doc comment', () {
      expect(commentsIn('/// Docs.\nvoid f() {}'), ['/// Docs.']);
    });

    test('finds a language version comment', () {
      expect(commentsIn('// @dart = 3.10\nvoid f() {}'), ['// @dart = 3.10']);
    });

    test('finds the comments of a file that holds nothing else', () {
      expect(
        commentsIn('''
// a
/* b */
// c
'''),
        ['// a', '// c'],
      );
    });

    test('finds none in a nested, multi-line /* */ block comment', () {
      expect(
        commentsIn('''
/* outer /* inner // a */
// b */
x // c'''),
        ['// c'],
      );
    });

    test('finds none in a string literal', () {
      expect(commentsIn("final s = 'a // b';"), isEmpty);
    });

    test('ends a raw string at its quote, after a backslash', () {
      expect(commentsIn(r"final p = r'C:\'; // c"), ['// c']);
    });

    test('finds none in an interpolation inside a string literal', () {
      expect(commentsIn(r"""final s = '$x ${"// a"} // b';"""), isEmpty);
    });
  });

  test('commentsBefore lists the comments right before a token, in order', () {
    final unit = parseDart('''
// a
/* b */
/// c
void f() {}
''').unit;

    expect(commentsBefore(unit.beginToken).map((comment) => comment.lexeme), [
      '// a',
      '/* b */',
      '/// c',
    ]);
  });
}
