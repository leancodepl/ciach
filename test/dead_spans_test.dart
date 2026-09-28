import 'package:ciach/ciach.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;
import 'package:test/test.dart';

void main() {
  const rootPath = '/root';
  const path = '/root/lib/a.dart';

  UnusedDeclaration finding(String name, (int, int) start, (int, int) end) =>
      .new(
        name: name,
        kind: .function,
        filePath: 'lib/a.dart',
        line: start.$1 + 1,
        column: start.$2 + 1,
        isPrivate: false,
        range: (
          startLine: start.$1,
          startColumn: start.$2,
          endLine: end.$1,
          endColumn: end.$2,
        ),
      );

  group('DeadSpans.ownerOf', () {
    const inside = Position(line: 1, character: 0);

    test('picks the span that ends later when two start together', () {
      final short = finding('short', (0, 0), (2, 0));
      final long = finding('long', (0, 0), (5, 0));
      for (final order in [
        [short, long],
        [long, short],
      ]) {
        expect(DeadSpans.of(order, rootPath).ownerOf(path, inside), long);
      }
    });

    test('picks the span that starts earlier', () {
      final inner = finding('inner', (1, 0), (2, 0));
      final outer = finding('outer', (0, 0), (5, 0));
      for (final order in [
        [inner, outer],
        [outer, inner],
      ]) {
        expect(DeadSpans.of(order, rootPath).ownerOf(path, inside), outer);
      }
    });

    test('is null outside every span', () {
      final spans = DeadSpans.of([finding('f', (0, 0), (2, 0))], rootPath);
      expect(spans.ownerOf(path, const .new(line: 3, character: 0)), isNull);
      expect(spans.ownerOf('/root/lib/b.dart', inside), isNull);
    });
  });
}
