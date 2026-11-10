/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';

void main() {
  /// The token of [text], of the [type] that the server gives it.
  SemanticToken token(String type, String text) => .new(
    line: 0,
    character: 0,
    length: text.length,
    type: type,
    modifiers: const {},
    text: text,
  );

  test('the keywords are those after the last annotation, before the name', () {
    // `@Meta(const []) final int x;`, whose code starts at `x`.
    final declaration = ResolvedDeclaration(
      relativePath: 'lib/a.dart',
      symbol: symbol('x', kind: .variable),
      leadingMetadata: [
        token('annotation', '@'),
        token('class', 'Meta'),
        token('annotation', '('),
        token('keyword', 'const'),
        token('annotation', ')'),
        token('keyword', 'final'),
        token('class', 'int'),
      ],
    );
    // `/// Doc.` and `abstract class Api`, whose code starts at `abstract`.
    final type = ResolvedDeclaration(
      relativePath: 'lib/a.dart',
      symbol: symbol('Api', kind: .class$),
      leadingMetadata: [token('comment', '/// Doc.')],
      tokensBeforeName: [
        token('keyword', 'abstract'),
        token('keyword', 'class'),
      ],
    );

    expect(declaration.keywords, {'final'});
    expect(type.keywords, {'abstract', 'class'});
  });
}
