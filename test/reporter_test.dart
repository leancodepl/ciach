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
import 'package:xml/xml.dart';

void main() {
  FinderResult resultWith(
    List<UnusedDeclaration> unused, {
    List<UnusedDeclaration> docOnly = const [],
    List<String> emptyFiles = const [],
    List<String> emptyVariants = const [],
    List<RecoveredReference> recoveredReferences = const [],
    List<AnalysisProblem> problems = const [],
  }) => .new(
    unused: unused,
    docOnly: docOnly,
    filesScanned: 3,
    declarationsChecked: 10,
    elapsed: const .new(seconds: 1),
    emptyFiles: emptyFiles,
    emptyVariants: emptyVariants,
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
    bool removalBlocked = false,
    String? hint,
    List<DeadReferrer> onlyReferencedFrom = const [],
  }) => .new(
    name: name,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    isPrivate: isPrivate,
    container: container,
    removalBlocked: removalBlocked,
    hint: hint,
    onlyReferencedFrom: onlyReferencedFrom,
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

    test(
      'emits a ::warning annotation on the first line of each empty file',
      () {
        final out = Reporter.github(
          resultWith(
            const [],
            emptyFiles: ['lib/blank.dart'],
            emptyVariants: ['lib/web.dart'],
          ),
          pathPrefix: 'app',
        );
        expect(out, '''
::warning file=app/lib/blank.dart,line=1,col=1,title=Empty file::Has nothing but comments and library, import or part-of directives
::warning file=app/lib/web.dart,line=1,col=1,title=Empty file::Has nothing but comments and library, import or part-of directives — a conditional-import variant: remove its `if` clause and the file by hand
''');
      },
    );

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

  const root = (qualifiedName: '_root', filePath: 'lib/a.dart', line: 1);
  const other = (qualifiedName: '_other', filePath: 'lib/b.dart', line: 7);

  group('Reporter.text', () {
    test('separates columns and notes with two spaces', () {
      final out = Reporter.text(
        resultWith([
          decl(
            removalBlocked: true,
            hint: 'a hint',
            onlyReferencedFrom: [root, other],
          ),
        ]),
      );
      expect(
        out,
        contains(
          '  3:5  function  foo  (public)'
          '  (unsafe to auto-remove — remove manually)'
          '  (a hint)'
          '  (only referenced from dead _root (lib/a.dart:1) and 1 more)\n',
        ),
      );
    });

    test('adds nothing after the visibility of a plain finding', () {
      final out = Reporter.text(resultWith([decl()]));
      expect(out, contains('  3:5  function  foo  (public)\n'));
    });

    test('separates recovered references by file, like findings', () {
      final out = Reporter.text(
        resultWith(
          const [],
          recoveredReferences: [
            warning(),
            warning(name: 'qux', filePath: 'lib/c.dart', line: 12),
          ],
        ),
      );
      expect(
        out,
        contains('''
lib/a.dart
  4:7  A.baz  used at lib/b.dart:9:2

lib/c.dart
  12:7  A.qux  used at lib/b.dart:9:2

'''),
      );
    });

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

  group('Reporter.azure', () {
    test('emits one task.logissue warning per finding, doc-only too', () {
      final out = Reporter.azure(
        resultWith(
          [decl()],
          docOnly: [decl(name: 'docOnlyThing', line: 9)],
          emptyFiles: ['lib/blank.dart'],
        ),
        pathPrefix: 'app',
      );
      expect(out, '''
##vso[task.logissue type=warning;sourcepath=app/lib/a.dart;linenumber=3;columnnumber=5]Unused declaration: Unused function 'foo'
##vso[task.logissue type=warning;sourcepath=app/lib/blank.dart;linenumber=1;columnnumber=1]Empty file: Has nothing but comments and library, import or part-of directives
##vso[task.logissue type=warning;sourcepath=app/lib/a.dart;linenumber=9;columnnumber=5]Referenced only from a doc comment: function 'docOnlyThing' has no code references, only a dartdoc link
''');
    });

    test('escapes percent signs, semicolons and brackets', () {
      final out = Reporter.azure(
        resultWith([decl(name: '50%', filePath: 'lib/a;b].dart')]),
      );
      expect(out, contains('sourcepath=lib/a%3Bb%5D.dart;'));
      expect(out, contains("Unused function '50%AZP25'"));
    });

    test('leaves out the position a problem lacks', () {
      final out = Reporter.azure(
        resultWith(
          const [],
          problems: [problem(line: null, column: null, name: null)],
        ),
      );
      expect(
        out,
        '##vso[task.logissue type=warning;sourcepath=lib/a.dart]Could not analyze: '
        'Could not find the references; kept. '
        'Cause: Null check operator used on a null value\n',
      );
    });

    test('produces no output when nothing is found', () {
      expect(Reporter.azure(resultWith(const [])), isEmpty);
    });
  });

  group('Reporter.teamCity', () {
    test('declares each inspection type once, before its first use', () {
      final out = Reporter.teamCity(
        resultWith(
          [decl(), decl(name: 'bar', line: 7)],
          docOnly: [decl(name: 'docOnlyThing', line: 9)],
        ),
        pathPrefix: 'app',
      );
      expect(out, '''
##teamcity[inspectionType id='ciach.unused-declaration' name='Unused declaration' category='ciach' description='Unused declaration']
##teamcity[inspection typeId='ciach.unused-declaration' message='Unused function |'foo|'' file='app/lib/a.dart' line='3' SEVERITY='WARNING']
##teamcity[inspection typeId='ciach.unused-declaration' message='Unused function |'bar|'' file='app/lib/a.dart' line='7' SEVERITY='WARNING']
##teamcity[inspectionType id='ciach.doc-only' name='Referenced only from a doc comment' category='ciach' description='Referenced only from a doc comment']
##teamcity[inspection typeId='ciach.doc-only' message='function |'docOnlyThing|' has no code references, only a dartdoc link' file='app/lib/a.dart' line='9' SEVERITY='WEAK WARNING']
''');
    });

    test('escapes bars, brackets and newlines', () {
      final out = Reporter.teamCity(
        resultWith([decl(name: 'a|b', hint: '[x]\ny')]),
      );
      expect(out, contains("message='Unused function |'a||b|' — |[x|]|ny'"));
    });

    test('escapes the Unicode line breaks', () {
      final out = Reporter.teamCity(
        resultWith([decl(hint: 'a\u0085b\u2028c\u2029d')]),
      );
      expect(out, contains('a|xb|lc|pd'));
    });

    test('leaves out the line a problem lacks', () {
      final out = Reporter.teamCity(
        resultWith(
          const [],
          problems: [problem(line: null, column: null, name: null)],
        ),
      );
      expect(out, isNot(contains('line=')));
      expect(out, contains("file='lib/a.dart' SEVERITY='WARNING'"));
    });

    test('produces no output when nothing is found', () {
      expect(Reporter.teamCity(resultWith(const [])), isEmpty);
    });
  });

  group('Reporter.sarif', () {
    test('lists every rule and one result per finding', () {
      final log =
          jsonDecode(
                Reporter.sarif(
                  resultWith(
                    [decl()],
                    docOnly: [decl(name: 'docOnlyThing', line: 9)],
                  ),
                  pathPrefix: 'app',
                ),
              )
              as Map<String, Object?>;
      expect(log['version'], '2.1.0');
      final [run as Map<String, Object?>] = log['runs']! as List<Object?>;
      final driver =
          (run['tool']! as Map<String, Object?>)['driver']!
              as Map<String, Object?>;
      expect(driver['name'], 'ciach');
      expect(
        [
          for (final rule in driver['rules']! as List<Object?>)
            (rule! as Map<String, Object?>)['id'],
        ],
        [
          'unused-declaration',
          'empty-file',
          'doc-only',
          'recovered-reference',
          'not-analyzed',
        ],
      );
      expect(run['results'], [
        {
          'ruleId': 'unused-declaration',
          'ruleIndex': 0,
          'level': 'warning',
          'message': {'text': "Unused function 'foo'"},
          'locations': [
            {
              'physicalLocation': {
                'artifactLocation': {'uri': 'app/lib/a.dart'},
                'region': {'startLine': 3, 'startColumn': 5},
              },
            },
          ],
        },
        {
          'ruleId': 'doc-only',
          'ruleIndex': 2,
          'level': 'note',
          'message': {
            'text':
                "function 'docOnlyThing' has no code references, only a dartdoc link",
          },
          'locations': [
            {
              'physicalLocation': {
                'artifactLocation': {'uri': 'app/lib/a.dart'},
                'region': {'startLine': 9, 'startColumn': 5},
              },
            },
          ],
        },
      ]);
    });

    test('percent-encodes the uri', () {
      final out = Reporter.sarif(
        resultWith([decl(filePath: 'lib/my widget#1.dart')]),
      );
      expect(out, contains('"uri": "lib/my%20widget%231.dart"'));
    });

    test('leaves out the region a problem lacks', () {
      final log =
          jsonDecode(
                Reporter.sarif(
                  resultWith(
                    const [],
                    problems: [problem(line: null, column: null)],
                  ),
                ),
              )
              as Map<String, Object?>;
      expect(jsonEncode(log), isNot(contains('region')));
    });
  });

  group('Reporter.checkstyle', () {
    test('groups the findings by file', () {
      final out = Reporter.checkstyle(
        resultWith(
          [decl(), decl(name: 'bar', filePath: 'lib/b.dart', line: 7)],
          docOnly: [decl(name: 'docOnlyThing', line: 9)],
        ),
        pathPrefix: 'app',
      );
      expect(out, """
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle version="4.3">
  <file name="app/lib/a.dart">
    <error line="3" column="5" severity="warning" message="Unused function 'foo'" source="ciach.unused-declaration"/>
    <error line="9" column="5" severity="info" message="function 'docOnlyThing' has no code references, only a dartdoc link" source="ciach.doc-only"/>
  </file>
  <file name="app/lib/b.dart">
    <error line="7" column="5" severity="warning" message="Unused function 'bar'" source="ciach.unused-declaration"/>
  </file>
</checkstyle>
""");
    });

    /// The `name` of the only file and the `message` of its only error.
    (String, String) nameAndMessage(String out) {
      final file = XmlDocument.parse(out).findAllElements('file').single;
      return (
        file.getAttribute('name')!,
        file.findElements('error').single.getAttribute('message')!,
      );
    }

    test('escapes markup', () {
      final out = Reporter.checkstyle(
        resultWith([decl(name: 'a<b>&"c"', filePath: 'lib/a&b.dart')]),
      );
      expect(nameAndMessage(out), (
        'lib/a&b.dart',
        """Unused function 'a<b>&"c"'""",
      ));
    });

    test('keeps whitespace and drops what XML cannot hold', () {
      final out = Reporter.checkstyle(
        resultWith([decl(hint: 'a\r\n\tb\x1Bc')]),
      );
      expect(out, isNot(contains('&#x1B;')));
      expect(nameAndMessage(out).$2, endsWith('a\r\n\tbc'));
    });

    test('has no files when nothing is found', () {
      expect(Reporter.checkstyle(resultWith(const [])), '''
<?xml version="1.0" encoding="UTF-8"?>
<checkstyle version="4.3"/>
''');
    });
  });

  group('Reporter.gitlab', () {
    List<Object?> issues(FinderResult result) =>
        jsonDecode(Reporter.gitlab(result, pathPrefix: 'app')) as List<Object?>;

    test('emits one Code Quality issue per finding', () {
      final [unused, docOnly] = issues(
        resultWith([decl()], docOnly: [decl(name: 'docOnlyThing', line: 9)]),
      );
      expect(unused, {
        'description': "Unused function 'foo'",
        'check_name': 'unused-declaration',
        'fingerprint': isA<String>(),
        'severity': 'minor',
        'location': {
          'path': 'app/lib/a.dart',
          'lines': {'begin': 3},
        },
      });
      expect(docOnly, containsPair('severity', 'info'));
    });

    test('keeps a fingerprint when only the line changes', () {
      String fingerprintAt(int line) =>
          (issues(resultWith([decl(line: line)])).single!
                  as Map<String, Object?>)['fingerprint']!
              as String;
      expect(fingerprintAt(3), fingerprintAt(30));
      expect(fingerprintAt(3), matches(RegExp(r'^[0-9a-f]{16}$')));
    });

    test('tells identical findings in one file apart', () {
      final fingerprints = {
        for (final issue in issues(resultWith([decl(), decl(line: 8)])))
          (issue! as Map<String, Object?>)['fingerprint'],
      };
      expect(fingerprints, hasLength(2));
    });

    test('puts a finding without a line on the first one', () {
      final [issue as Map<String, Object?>] = issues(
        resultWith(const [], problems: [problem(line: null, column: null)]),
      );
      expect(issue['location'], {
        'path': 'app/lib/a.dart',
        'lines': {'begin': 1},
      });
    });

    test('is an empty list when nothing is found', () {
      expect(issues(resultWith(const [])), isEmpty);
    });
  });

  test('Reporter.github joins the hint and the dead referrer with dashes', () {
    final out = Reporter.github(
      resultWith([
        decl(hint: 'a hint', onlyReferencedFrom: [root]),
      ]),
    );
    expect(
      out,
      contains(
        "::Unused function 'foo' — a hint — only referenced from dead _root (lib/a.dart:1)",
      ),
    );
  });

  test('Reporter.json lists every dead referrer', () {
    final json =
        jsonDecode(
              Reporter.json(
                resultWith([
                  decl(onlyReferencedFrom: [root, other]),
                ]),
              ),
            )
            as Map<String, Object?>;
    final unused = json['unused']! as List<Object?>;
    expect((unused.single! as Map)['onlyReferencedFrom'], [
      {'qualifiedName': '_root', 'file': 'lib/a.dart', 'line': 1},
      {'qualifiedName': '_other', 'file': 'lib/b.dart', 'line': 7},
    ]);
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

    test('lists the empty files and counts them', () {
      final json =
          jsonDecode(
                Reporter.json(
                  resultWith(
                    const [],
                    emptyFiles: ['lib/blank.dart'],
                    emptyVariants: ['lib/web.dart'],
                  ),
                ),
              )
              as Map<String, Object?>;
      final summary = json['summary']! as Map<String, Object?>;
      expect(summary['emptyFileCount'], 1);
      expect(summary['emptyVariantCount'], 1);
      expect(json['emptyFiles'], ['lib/blank.dart']);
      expect(json['emptyVariants'], ['lib/web.dart']);
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
          emptyFiles: ['lib/blank.dart', 'lib/zero.dart'],
          emptyVariants: ['lib/web.dart'],
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
        '''
lib/a.dart
  3:5   function  dangling  (public)
  18:5  function  _private  (private)

Empty files (3) · nothing but comments and library, import or part-of directives
lib/blank.dart
lib/web.dart  (a conditional-import variant: remove its `if` clause and the file by hand)
lib/zero.dart

Referenced only from doc comments (1) · not counted, never removed
lib/a.dart
  41:5  function  docOnly  (public)

Recovered references (1) · missed by find-references; kept
lib/a.dart
  4:7  A.baz  used at lib/b.dart:9:2

Not analyzed (2) · the analysis failed here
  Could not find the references; kept.
    Null check operator used on a null value
    lib/b.dart
      65:11  A.foo
  Could not read these files; nothing reported.
    Permission denied
    lib/secret.dart
  Likely a Dart SDK bug; -v shows the stack traces.

Found 2 unused declarations in 1 file (scanned 3 files, 10 declarations, 1.0s) · 3 empty files · 1 doc-only · 1 recovered · 2 not analyzed''',
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
        const .new(
          filesChanged: 2,
          deletedFiles: [(filePath: 'lib/empty.dart', unlinkedFrom: [])],
          emptiedContainers: [],
        ),
        removed: 3,
        blocked: 1,
        notes: ['Foo._: prefer `abstract final class`'],
      );
      expect(
        text,
        'Removed 3 unused declarations from 2 files. 1 left in place — unsafe '
        'to auto-remove. Deleted 1 empty file: lib/empty.dart. '
        "Run 'dart format' to tidy up spacing.\n"
        'Note: Foo._: prefer `abstract final class`',
      );
    });

    test('leaves out the declarations when only empty files went', () {
      final text = Reporter.removal(
        const .new(
          filesChanged: 0,
          deletedFiles: [(filePath: 'lib/blank.dart', unlinkedFrom: [])],
          emptiedContainers: [],
        ),
      );
      expect(
        text,
        "Deleted 1 empty file: lib/blank.dart. Run 'dart format' to tidy up "
        'spacing.',
      );
    });

    test('lists the empty declarations it kept', () {
      final text = Reporter.removal(
        const .new(
          filesChanged: 2,
          deletedFiles: [],
          emptiedContainers: [
            (filePath: 'lib/a.dart', name: 'Painter'),
            (filePath: 'lib/b.dart', name: 'Parsing'),
          ],
        ),
        removed: 2,
      );
      expect(
        text,
        'Removed 2 unused declarations from 2 files. Kept 2 empty '
        'declarations that other code still uses: Painter (lib/a.dart), '
        "Parsing (lib/b.dart). Run 'dart format' to tidy up spacing.",
      );
    });

    test('says so when the user declined', () {
      expect(Reporter.removal(null), 'Skipped removal.');
    });
  });
}
