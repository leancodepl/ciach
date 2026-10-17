/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/symbols.dart';
import 'package:test/test.dart';

void main() {
  test('`constructorName` names a constructor without its class', () {
    expect(
      [
        constructorName('Foo.named', 'Foo'),
        constructorName('Foo', 'Foo'),
        constructorName('', 'Foo'),
        constructorName('_Foo._internal', '_Foo'),
        constructorName('named', null),
      ],
      ['named', 'new', 'new', '_internal', 'named'],
    );
  });
}
