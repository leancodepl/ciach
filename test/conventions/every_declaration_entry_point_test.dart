/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';

void main() {
  group('EntryPoint.everyDeclaration', () {
    final rule = EntryPoint.everyDeclaration(
      reason: 'read by a tool',
      files: const ['pigeons/messages.dart'],
    );

    test('matches every declaration in its files, members included', () {
      for (final (name, kind, container) in [
        ('Message', SymbolKind.class$, null),
        ('text', SymbolKind.field, 'Message'),
        ('send', SymbolKind.method, 'MessageApi'),
        ('Code', SymbolKind.enum$, null),
        ('ok', SymbolKind.enumMember, 'Code'),
        ('helper', SymbolKind.function, null),
      ]) {
        expect(
          EntryPoints([rule]).match(
            declarationAt(
              'pigeons/messages.dart',
              symbol(name, kind: kind),
              container,
            ),
          ),
          same(rule),
          reason: 'for $name',
        );
      }
    });

    test('matches nothing in other files', () {
      expect(
        rule.matches(
          declarationAt('lib/messages.dart', symbol('Message'), null),
        ),
        isFalse,
      );
    });

    test('`within` limits the rule to the files of a nested package', () {
      final nested = rule.within('app');
      expect(
        (
          nested.matches(
            declarationAt('app/pigeons/messages.dart', symbol('Message'), null),
          ),
          nested.matches(
            declarationAt('pigeons/messages.dart', symbol('Message'), null),
          ),
        ),
        (true, false),
      );
    });

    test('throws an `ArgumentError` without a file glob', () {
      expect(
        () => EntryPoint.everyDeclaration(reason: 'read by a tool', files: []),
        throwsArgumentError,
      );
    });
  });
}
