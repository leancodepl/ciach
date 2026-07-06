/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:test/test.dart';
import 'package:unused_declarations_finder/src/reporter.dart';
import 'package:unused_declarations_finder/unused_declarations_finder.dart';

void main() {
  FinderResult resultWith(List<UnusedDeclaration> unused) => .new(
    unused: unused,
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
  });
}
