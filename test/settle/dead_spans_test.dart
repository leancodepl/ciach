import 'package:ciach/ciach.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/source/clause_entries.dart';
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

  group('DeadSpans.ownerOf in a clause entry', () {
    // Line 3 is `class Held with C<Arg>, D<Other> {}`, and removing `C` and `D`
    // deletes ` with C<Arg>, D<Other>`.
    const clause = (startLine: 3, startColumn: 10, endLine: 3, endColumn: 32);
    const atC = Position(line: 3, character: 16);
    const atArg = Position(line: 3, character: 18);
    const atOther = Position(line: 3, character: 26);

    /// A type declared on [line] that `--remove` also removes from the
    /// clause on line 3, where its entry starts at [startColumn] and ends at
    /// [endColumn].
    UnusedDeclaration clauseOnly(
      String name,
      int line,
      int startColumn,
      int endColumn,
    ) {
      final range = (
        startLine: 3,
        startColumn: startColumn,
        endLine: 3,
        endColumn: endColumn,
      );
      return finding(name, (line, 0), (line, 10)).copyWith(
        coupledRemovals: [
          (
            filePath: 'lib/a.dart',
            kind: clauseCutKind,
            range: range,
            fullRange: range,
            cut: clause,
          ),
        ],
      );
    }

    final c = clauseOnly('C', 0, 16, 22);
    final d = clauseOnly('D', 1, 24, 32);

    test('keeps a reference to the type at the start of its own entry', () {
      final spans = DeadSpans.of([c], rootPath);

      expect(spans.ownerOf(path, atC), isNull);
      expect(spans.ownersOf(path, atC), [c]);
    });

    test('assigns a reference in type arguments to the entry holding it', () {
      for (final order in [
        [c, d],
        [d, c],
      ]) {
        final spans = DeadSpans.of(order, rootPath);
        expect(spans.ownerOf(path, atArg), c);
        expect(spans.ownerOf(path, atOther), d);
      }
    });

    test('deletes a reference in a clause of a removed declaration', () {
      final held = finding('Held', (3, 0), (3, 35));

      expect(DeadSpans.of([c, held], rootPath).ownerOf(path, atC), held);
    });
  });

  group('DeadSpans.sameAs', () {
    test('compares the ranges, not the findings that own them', () {
      DeadSpans spans(List<(int, int)> ends) => DeadSpans.of([
        for (final end in ends) finding('f', (0, 0), end),
      ], rootPath);
      expect(spans([(2, 0)]).sameAs(spans([(2, 0)])), isTrue);
      expect(spans([(2, 0)]).sameAs(spans([(3, 0)])), isFalse);
      expect(spans([(2, 0)]).sameAs(spans([(2, 0), (3, 0)])), isFalse);
      expect(spans([(2, 0)]).sameAs(DeadSpans.empty), isFalse);
    });
  });
}
