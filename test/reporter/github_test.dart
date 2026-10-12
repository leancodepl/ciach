import 'package:ciach/src/reporter.dart';
import 'package:test/test.dart';

import '../support/reporter.dart';

void main() {
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

  test('Reporter.github joins the hint and the dead referrer with dashes', () {
    final out = Reporter.github(
      resultWith([
        decl(hint: 'a hint', onlyReferencedFrom: [rootReferrer]),
      ]),
    );
    expect(
      out,
      contains(
        "::Unused function 'foo' — a hint — only referenced from dead _root (lib/a.dart:1)",
      ),
    );
  });
}
