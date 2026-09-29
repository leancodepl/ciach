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
import 'package:ciach/src/style.dart';
import 'package:test/test.dart';

void main() {
  FinderResult resultWith(
    List<UnusedDeclaration> unused, {
    List<UnusedDeclaration> docOnly = const [],
    List<RecoveredReference> recoveredReferences = const [],
    List<AnalysisProblem> problems = const [],
  }) => .new(
    unused: unused,
    docOnly: docOnly,
    filesScanned: 3,
    declarationsChecked: 10,
    elapsed: const .new(seconds: 1),
    recoveredReferences: recoveredReferences,
    problems: problems,
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

  AnalysisProblem problem({
    String summary = 'Could not find the references; kept.',
    String cause = 'Null check operator used on a null value',
    String filePath = 'lib/a.dart',
    int? line = 3,
    int? column = 5,
    String? name = 'A.foo',
    String? detail = '#0      Foo.bar',
  }) => .new(
    summary: summary,
    cause: cause,
    filePath: filePath,
    line: line,
    column: column,
    name: name,
    detail: detail,
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
      expect(out, contains('not counted, never removed'));
      // The doc-only entry appears after the "not counted..." label, not
      // mixed into the unused listing above it.
      expect(out.indexOf('not counted'), greaterThan(out.indexOf('trulyDead')));
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

  group('problems', () {
    test('json carries them in-band', () {
      final decoded =
          jsonDecode(Reporter.json(resultWith(const [], problems: [problem()])))
              as Map<String, Object?>;
      expect(decoded['problems'], [
        {
          'summary': 'Could not find the references; kept.',
          'cause': 'Null check operator used on a null value',
          'file': 'lib/a.dart',
          'line': 3,
          'column': 5,
          'name': 'A.foo',
          'detail': '#0      Foo.bar',
        },
      ]);
    });

    test('github annotates each, with what position is known', () {
      final github = Reporter.github(
        resultWith(
          const [],
          problems: [problem(), problem(line: null, column: null, name: null)],
        ),
        pathPrefix: 'pkg',
      );
      expect(
        github,
        '::warning file=pkg/lib/a.dart,line=3,col=5,title=Could not analyze'
        "::'A.foo': Could not find the references; kept. "
        'Cause: Null check operator used on a null value\n'
        '::warning file=pkg/lib/a.dart,title=Could not analyze'
        '::Could not find the references; kept. '
        'Cause: Null check operator used on a null value\n',
      );
    });
  });

  group('Reporter.text sections', () {
    test('lays out every section below the findings, and counts them', () {
      final text = Reporter.text(
        resultWith(
          [
            decl(name: 'dangling'),
            decl(name: '_private', line: 18, isPrivate: true),
          ],
          docOnly: [decl(name: 'docOnly', line: 41)],
          recoveredReferences: [warning()],
          problems: [
            problem(filePath: 'lib/b.dart', line: 65, column: 11),
            problem(
              summary: 'Could not read these files; nothing reported.',
              cause: 'Permission denied',
              filePath: 'lib/secret.dart',
              line: null,
              column: null,
              name: null,
              detail: null,
            ),
          ],
        ),
      );
      expect(
        text,
        'lib/a.dart\n'
        '  3:5   function  dangling  (public)\n'
        '  18:5  function  _private  (private)\n'
        '\n'
        'Referenced only from doc comments (1) · not counted, never removed\n'
        'lib/a.dart\n'
        '  41:5  function  docOnly  (public)\n'
        '\n'
        'Recovered references (1) · missed by find-references; kept\n'
        'lib/a.dart\n'
        '  4:7  A.baz  used at lib/b.dart:9:2\n'
        '\n'
        'Not analyzed (2) · the analysis failed here\n'
        '  Could not find the references; kept.\n'
        '    Null check operator used on a null value\n'
        '    lib/b.dart\n'
        '      65:11  A.foo\n'
        '  Could not read these files; nothing reported.\n'
        '    Permission denied\n'
        '    lib/secret.dart\n'
        '  Likely a Dart SDK bug; -v shows the stack traces.\n'
        '\n'
        'Found 2 unused declarations in 1 file (scanned 3 files, 10 '
        'declarations, 1.0s) · 1 doc-only · 1 recovered · 2 not analyzed',
      );
    });

    test('leaves out the sections with nothing in them', () {
      final text = Reporter.text(resultWith(const []));
      expect(
        text,
        'No unused declarations found (scanned 3 files, 10 declarations, 1.0s)',
      );
    });

    test(
      'lists the first few of a cause unless verbose, which adds the stack',
      () {
        final result = resultWith(
          const [],
          problems: [for (var i = 1; i <= 3; i++) problem(line: i)],
        );
        final short = Reporter.text(result, maxListed: 2);
        expect(short, contains('      2:5  A.foo'));
        expect(short, isNot(contains('      3:5  A.foo')));
        expect(short, contains('    … and 1 more (-v lists them all)'));
        expect(short, contains('-v shows the stack traces'));

        final verbose = Reporter.text(result, verbose: true, maxListed: 2);
        expect(verbose, contains('      3:5  A.foo'));
        expect(verbose, contains('    Stack trace of the first:'));
        expect(verbose, contains('      #0      Foo.bar'));
        expect(verbose, isNot(contains('-v')));
      },
    );

    test('colors by role', () {
      const style = Style(enabled: true);
      expect(
        Reporter.text(resultWith(const []), style: style),
        startsWith(
          '\x1b[32mNo unused declarations found\x1b[39m \x1b[2m(scanned',
        ),
      );
      final text = Reporter.text(
        resultWith([decl()], problems: [problem()]),
        style: style,
      );
      // A caution heading, a failure's cause, the findings as attention.
      expect(text, contains('\x1b[33m\x1b[1mNot analyzed (1)\x1b[22m\x1b[39m'));
      expect(
        text,
        contains('\x1b[31mNull check operator used on a null value\x1b[39m'),
      );
      expect(
        text,
        contains('\x1b[1m\x1b[33mFound 1 unused declaration in 1 file'),
      );
    });
  });

  group('Reporter.removal', () {
    test('says what was removed, left and deleted, with the hints it took', () {
      final text = Reporter.removal(
        const RemovalResult(
          filesChanged: 2,
          deletedFiles: [(filePath: 'lib/empty.dart', unlinkedFrom: [])],
        ),
        removed: 3,
        blocked: 1,
        notes: ['Foo._: prefer `abstract final class`'],
      );
      expect(
        text,
        'Removed 3 unused declarations from 2 files. 1 left in place — unsafe '
        'to auto-remove. Deleted 1 now-empty file: lib/empty.dart. '
        "Run 'dart format' to tidy up spacing.\n"
        'Note: Foo._: prefer `abstract final class`',
      );
    });

    test('says so when the user declined', () {
      expect(Reporter.removal(null), 'Skipped removal.');
    });
  });
}
