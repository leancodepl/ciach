import 'package:ciach/src/reporter.dart';
import 'package:ciach/src/style.dart';
import 'package:test/test.dart';

import '../support/reporter.dart';

void main() {
  group('Reporter.text', () {
    test('separates columns and notes with two spaces', () {
      final out = Reporter.text(
        resultWith([
          decl(
            removalBlocked: true,
            hint: 'a hint',
            onlyReferencedFrom: [rootReferrer, otherReferrer],
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
        '''
lib/a.dart
  3:5   function  dangling  (public)
  18:5  function  _private  (private)

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

Found 2 unused declarations in 1 file (scanned 3 files, 10 declarations, 1.0s) · 1 doc-only · 1 recovered · 2 not analyzed''',
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
}
