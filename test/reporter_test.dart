/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/reporter.dart';
import 'package:test/test.dart';

void main() {
  FinderResult resultWith(
    List<UnusedDeclaration> unused, {
    List<UnusedDeclaration> docOnly = const [],
  }) => .new(
    unused: unused,
    docOnly: docOnly,
    filesScanned: 3,
    declarationsChecked: 10,
    elapsed: const .new(seconds: 1),
  );

  UnusedDeclaration decl({
    String name = 'foo',
    SymbolKind kind = .function,
    String filePath = 'lib/a.dart',
    int line = 3,
    int column = 5,
    bool isPrivate = false,
    String? container,
  }) => .new(
    name: name,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    isPrivate: isPrivate,
    container: container,
    range: (
      startLine: line - 1,
      startColumn: column - 1,
      endLine: line - 1,
      endColumn: column - 1 + name.length,
    ),
  );

  group('Reporter.github', () {
    test('emits one ::warning annotation per finding', () {
      final out = Reporter.github(
        resultWith([
          decl(),
          decl(
            name: '_bar',
            kind: .field,
            line: 8,
            column: 2,
            isPrivate: true,
            container: 'A',
          ),
        ]),
      );
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(2));
      expect(
        lines[0],
        "::warning file=lib/a.dart,line=3,col=5,title=Unused declaration::Unused function 'foo'",
      );
      expect(lines[1], contains("Unused private field 'A._bar'"));
    });

    test('prepends pathPrefix for sub-directory scans', () {
      final out = Reporter.github(resultWith([decl()]), pathPrefix: 'app');
      expect(out, contains('file=app/lib/a.dart,'));
    });

    test('escapes commas in properties and percent signs in the message', () {
      final out = Reporter.github(
        resultWith([decl(name: '50%', filePath: 'lib/a,b.dart')]),
      );
      expect(out, contains('file=lib/a%2Cb.dart,'));
      expect(out, contains("Unused function '50%25'"));
    });

    test('produces no output when nothing is unused', () {
      expect(Reporter.github(resultWith(const [])), isEmpty);
    });

    test('emits a lower-severity ::notice for doc-only findings', () {
      final out = Reporter.github(
        resultWith(const [], docOnly: [decl(name: 'docOnlyThing')]),
      );
      expect(out, startsWith('::notice '));
      expect(out, contains("docOnlyThing' has no code references"));
    });
  });

  group('Reporter.text', () {
    test('lists doc-only findings in a separate, labeled section', () {
      final out = Reporter.text(
        resultWith(
          [decl(name: 'trulyDead')],
          docOnly: [decl(name: 'onlyLinkedFromDocs')],
        ),
      );
      expect(out, contains('trulyDead'));
      expect(out, contains('onlyLinkedFromDocs'));
      expect(out, contains('not counted as unused, never removed'));
      // The doc-only entry appears after the "not counted..." label, not
      // mixed into the unused listing above it.
      expect(
        out.indexOf('not counted as unused'),
        greaterThan(out.indexOf('trulyDead')),
      );
    });

    test(
      'omits the doc-only section entirely when there is nothing to show',
      () {
        final out = Reporter.text(resultWith([decl()]));
        expect(out, isNot(contains('doc comment')));
      },
    );
  });

  group('Reporter.json', () {
    test('reports unused and docOnly as separate arrays', () {
      final json =
          jsonDecode(
                Reporter.json(
                  resultWith(
                    [decl(name: 'trulyDead')],
                    docOnly: [decl(name: 'onlyLinkedFromDocs')],
                  ),
                ),
              )
              as Map<String, Object?>;
      final summary = json['summary']! as Map<String, Object?>;
      expect(summary['unusedCount'], 1);
      expect(summary['docOnlyCount'], 1);
      final unused = json['unused']! as List<Object?>;
      final docOnly = json['docOnly']! as List<Object?>;
      expect((unused.single! as Map<String, Object?>)['name'], 'trulyDead');
      expect(
        (docOnly.single! as Map<String, Object?>)['name'],
        'onlyLinkedFromDocs',
      );
    });
  });
}
