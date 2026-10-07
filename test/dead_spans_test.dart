import 'dart:math';

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

  group('DeadSpans lookups', () {
    bool contains(UnusedDeclaration f, Position at) {
      final r = f.fullRange;
      final afterStart =
          at.line > r.startLine ||
          (at.line == r.startLine && at.character >= r.startColumn);
      final beforeEnd =
          at.line < r.endLine ||
          (at.line == r.endLine && at.character <= r.endColumn);
      return afterStart && beforeEnd;
    }

    // Starts earlier, or starts together and ends later; the first listed
    // wins a tie.
    bool outside(UnusedDeclaration a, UnusedDeclaration b) {
      final ra = a.fullRange;
      final rb = b.fullRange;
      if (ra.startLine != rb.startLine) {
        return ra.startLine < rb.startLine;
      }
      if (ra.startColumn != rb.startColumn) {
        return ra.startColumn < rb.startColumn;
      }
      if (ra.endLine != rb.endLine) {
        return ra.endLine > rb.endLine;
      }
      return ra.endColumn > rb.endColumn;
    }

    void expectMatchesScan(List<UnusedDeclaration> findings, int lines) {
      final spans = DeadSpans.of(findings, rootPath);
      for (var line = 0; line <= lines; line++) {
        for (var character = 0; character < 4; character++) {
          final at = Position(line: line, character: character);
          final owners = [
            for (final f in findings)
              if (contains(f, at)) f,
          ];
          UnusedDeclaration? outermost;
          for (final f in owners) {
            if (outermost == null || outside(f, outermost)) {
              outermost = f;
            }
          }
          expect(
            spans.ownersOf(path, at).toSet(),
            owners.toSet(),
            reason: '$at',
          );
          expect(spans.ownerOf(path, at), outermost, reason: '$at');
          expect(spans.covers(path, at), owners.isNotEmpty, reason: '$at');
        }
      }
      for (final f in findings) {
        final start = Position(
          line: f.fullRange.startLine,
          character: f.fullRange.startColumn,
        );
        expect(
          spans.enclosesInAnother(f, rootPath),
          findings.any((g) => !identical(g, f) && contains(g, start)),
          reason: f.name,
        );
      }
    }

    test('match a scan of every span, for nested spans', () {
      final random = Random(65);
      for (var run = 0; run < 200; run++) {
        final findings = <UnusedDeclaration>[];
        // Nested or disjoint ranges, some repeated, in a random order.
        void nest(int from, int to, int depth) {
          var line = from;
          while (line < to && depth < 4) {
            final end = min(to, line + 1 + random.nextInt(to - line));
            final f = finding('f${findings.length}', (line, 1), (end, 2));
            findings.add(f);
            if (random.nextInt(5) == 0) {
              findings.add(
                finding('dup${findings.length}', (line, 1), (end, 2)),
              );
            }
            nest(line + 1, end, depth + 1);
            line = end + 1 + random.nextInt(2);
          }
        }

        nest(0, 30, 0);
        findings.shuffle(random);
        expectMatchesScan(findings, 32);
      }
    });

    test('match a scan of every span, for overlapping spans', () {
      final findings = [
        finding('a', (0, 0), (5, 0)),
        finding('b', (3, 0), (8, 0)),
        finding('c', (4, 0), (4, 3)),
      ];
      expectMatchesScan(findings, 10);
    });
  });
}
