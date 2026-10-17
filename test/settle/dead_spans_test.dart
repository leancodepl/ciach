import 'package:ciach/ciach.dart';
import 'package:ciach/src/collect/candidates.dart';
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

  group('DeadSpans.ownerOf with a referenced type', () {
    // Line 3 is `class Held with C<Arg>, D {}`, and removing `C` and `D`
    // deletes ` with C<Arg>, D`.
    const clause = (startLine: 3, startColumn: 10, endLine: 3, endColumn: 26);
    const atC = Position(line: 3, character: 16);
    const atArg = Position(line: 3, character: 18);
    const atD = Position(line: 3, character: 24);

    /// A type declared on [line] that `--remove` also removes from the
    /// clause on line 3.
    UnusedDeclaration clauseOnly(String name, int line) =>
        finding(name, (line, 0), (line, 10)).copyWith(
          coupledRemovals: [
            (
              filePath: 'lib/a.dart',
              kind: clauseCutKind,
              range: clause,
              fullRange: clause,
              cut: clause,
            ),
          ],
        );

    DeclKey key(String name) => .new(path, name);

    test("keeps a reference that the type's own clause removal deletes", () {
      final c = clauseOnly('C', 0);
      final spans = DeadSpans.of([c], rootPath);

      expect(spans.ownerOf(path, atC, referenced: key('C')), isNull);
      expect(spans.ownerOf(path, atC), c);
    });

    test(
      'keeps a reference that a clause removal shared with another type deletes',
      () {
        final spans = DeadSpans.of([
          clauseOnly('C', 0),
          clauseOnly('D', 1),
        ], rootPath);

        expect(spans.ownerOf(path, atC, referenced: key('C')), isNull);
        expect(spans.ownerOf(path, atD, referenced: key('D')), isNull);
      },
    );

    test('deletes a reference in the type arguments of a removed entry', () {
      final c = clauseOnly('C', 0);

      expect(
        DeadSpans.of([
          c,
        ], rootPath).ownerOf(path, atArg, referenced: key('Arg')),
        c,
      );
    });

    test('deletes a reference in a clause of a removed declaration', () {
      final held = finding('Held', (3, 0), (3, 29));

      expect(
        DeadSpans.of([
          clauseOnly('C', 0),
          held,
        ], rootPath).ownerOf(path, atC, referenced: key('C')),
        held,
      );
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
