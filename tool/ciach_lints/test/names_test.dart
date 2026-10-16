/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach_lints/src/names.dart';
import 'package:test/test.dart';

void main() {
  group('`withoutLeadingUnderscores`', () {
    test('drops the underscore that starts `_items`', () {
      expect(withoutLeadingUnderscores('_items'), 'items');
    });

    test('drops both underscores that start `__items`', () {
      expect(withoutLeadingUnderscores('__items'), 'items');
    });

    test('keeps `items`, which starts with a letter', () {
      expect(withoutLeadingUnderscores('items'), 'items');
    });

    test('keeps the underscores after the first letter of `_all_items_`', () {
      expect(withoutLeadingUnderscores('_all_items_'), 'all_items_');
    });

    test('returns `null` for `_`', () {
      expect(withoutLeadingUnderscores('_'), isNull);
    });

    test('returns `null` for `__`, which has only underscores', () {
      expect(withoutLeadingUnderscores('__'), isNull);
    });
  });
}
