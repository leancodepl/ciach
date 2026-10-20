/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:leancode_site/leancode_site.dart';
import 'package:test/test.dart';

const _console = Language(
  'console',
  grammar:
      '''
{
  "name": "Console",
  "scopeName": "source.console",
  "patterns": [
$kShellPatterns
  ]
}''',
  isConsole: true,
);

void main() {
  setUpAll(() => initHighlighting([_console]));

  group('Language.named', () {
    test('returns a built-in language', () {
      expect(Language.named('dart'), same(Language.dart));
    });

    test('returns a language a site registered with `initHighlighting`', () {
      expect(Language.named('console'), same(_console));
    });

    test(
      'throws for a name that was not registered, listing the registered ones',
      () {
        expect(
          () => Language.named('rust'),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('dart, yaml, shell, json, console'),
            ),
          ),
        );
      },
    );
  });

  group('highlightLines', () {
    test('splits the source into one token list per line', () {
      final lines = highlightLines('a: 1\nb: 2\n', .yaml);
      expect(lines, hasLength(3));
      expect(lines.last, isEmpty);
    });

    test('marks the shell prompt of a console transcript', () {
      final lines = highlightLines(r'$ dart --version', _console);
      expect(lines, hasLength(1));
      expect(lines.single, isNotEmpty);
    });
  });
}
