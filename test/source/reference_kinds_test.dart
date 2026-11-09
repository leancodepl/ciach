/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:test/test.dart';

import '../support/fake_syntax.dart';

void main() {
  const path = '/project/lib/a.dart';
  final syntax = FakeSyntax()
    ..tokens[path] = [
      // `/// Doc for [Foo].`
      const .new(
        line: 0,
        character: 0,
        length: 13,
        type: 'comment',
        modifiers: {'documentation'},
        text: '/// Doc for [',
      ),
      const .new(
        line: 0,
        character: 13,
        length: 3,
        type: 'class',
        modifiers: {},
        text: 'Foo',
      ),
      // `void f() {}`
      const .new(
        line: 1,
        character: 0,
        length: 4,
        type: 'keyword',
        modifiers: {},
        text: 'void',
      ),
    ];
  final sources = SourceIndex(syntax);

  Location at(String path, int line, int character) => .new(
    path: path,
    range: .new(
      start: .new(line: line, character: character),
      end: .new(line: line, character: character + 1),
    ),
  );

  test(
    'a reference on a line that starts with a doc comment is a doc reference',
    () {
      expect(
        (
          sources.isDocReference(at(path, 0, 13)),
          sources.isDocReference(at(path, 1, 5)),
        ),
        (true, false),
      );
    },
  );

  test('a reference in a file without tokens is no doc reference', () {
    expect(sources.isDocReference(at('/project/lib/b.dart', 0, 5)), isFalse);
  });
}
