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
    List<RecoveredReference> recoveredReferences = const [],
  }) => .new(
    unused: unused,
    docOnly: docOnly,
    filesScanned: 3,
    declarationsChecked: 10,
    elapsed: const .new(seconds: 1),
    recoveredReferences: recoveredReferences,
  );

  RecoveredReference warning({
    String name = 'baz',
    String? container = 'A',
    String filePath = 'lib/a.dart',
    int line = 4,
    int column = 7,
    String usageFilePath = 'lib/b.dart',
    int usageLine = 9,
    int usageColumn = 2,
  }) => .new(
    name: name,
    container: container,
    filePath: filePath,
    line: line,
    column: column,
    usageFilePath: usageFilePath,
    usageLine: usageLine,
    usageColumn: usageColumn,
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

    test('emits a ::warning annotation for each recovered reference', () {
      final out = Reporter.github(
        resultWith(const [], recoveredReferences: [warning()]),
      );
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(1));
      expect(
        lines.single,
        startsWith('::warning file=lib/a.dart,line=4,col=7,'),
      );
      expect(lines.single, contains("::'A.baz' used at lib/b.dart:9:2"));
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

  group('Reporter.warningsText', () {
    test('emits one warning line per recovered reference', () {
      final out = Reporter.warningsText(
        resultWith(const [], recoveredReferences: [warning()]),
      );
      final lines = out.trimRight().split('\n');
      expect(lines, hasLength(1));
      expect(lines.single, startsWith("warning: 'A.baz' (lib/a.dart:4:7) "));
      expect(lines.single, contains('used at lib/b.dart:9:2'));
    });

    test('is empty when there are no recovered references', () {
      expect(Reporter.warningsText(resultWith([decl()])), isEmpty);
    });
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

    test('includes recovered references as a warnings array', () {
      final json =
          jsonDecode(
                Reporter.json(
                  resultWith(const [], recoveredReferences: [warning()]),
                ),
              )
              as Map<String, Object?>;
      final warnings = json['warnings']! as List<Object?>;
      final entry = warnings.single! as Map<String, Object?>;
      // `name`/`qualifiedName` mean the same as in `unused[]`.
      expect(entry['name'], 'baz');
      expect(entry['qualifiedName'], 'A.baz');
      expect(entry['file'], 'lib/a.dart');
      expect(entry['line'], 4);
      expect(entry['column'], 7);
      expect(entry['usageFile'], 'lib/b.dart');
      expect(entry['usageLine'], 9);
      expect(entry['usageColumn'], 2);
      expect(entry['message'], contains('used at lib/b.dart:9:2'));
    });

    test('warnings array is empty when there are no recovered references', () {
      final json =
          jsonDecode(Reporter.json(resultWith([decl()])))
              as Map<String, Object?>;
      expect(json['warnings'], isEmpty);
    });
  });
}
