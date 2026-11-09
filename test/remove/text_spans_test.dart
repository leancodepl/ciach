/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/remove/text_spans.dart';
import 'package:test/test.dart';

void main() {
  group('withIndentation', () {
    const content = '''
a();
  b();
c(); d();
''';

    test('moves an offset after indentation to the start of its line', () {
      expect(withIndentation(content, content.indexOf('b')), 5);
    });

    test('keeps an offset at the start of a line or of the file', () {
      expect(withIndentation(content, content.indexOf('c')), 12);
      expect(withIndentation(content, 0), 0);
    });

    test('keeps an offset that code precedes on its line', () {
      expect(withIndentation(content, content.indexOf('d')), 17);
    });
  });
}
