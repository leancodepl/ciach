@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('unused union members (opt-in --unused-union-members)', () {
    // The live member is constructed in bin/app.dart.
    Future<FinderResult> runUnions({required bool flag}) => Ciach(
      .new(
        rootPath: fixturePath,
        unusedUnionMembers: flag,
        includeGlobs: const ['lib/scenarios/unions.dart'],
      ),
    ).run();

    UnusedDeclaration? findByName(FinderResult result, String name) {
      for (final decl in result.unused) {
        if (decl.name == name) {
          return decl;
        }
      }
      return null;
    }

    test(
      'flag ON: a member matched only by a switch-statement case is '
      'reported but report-only (removal blocked, no coupled arms)',
      () async {
        final result = await runUnions(flag: true);
        final decl = findByName(result, 'StatementOnlySignal');
        expect(decl, isNotNull, reason: 'should be flagged dead');
        expect(decl!.kind, SymbolKind.class$);
        // Report-only: the class is surfaced so a human sees it is never
        // constructed, but `--remove` must not delete it or touch its arm.
        expect(decl.removalBlocked, isTrue);
        expect(decl.coupledRemovals, isEmpty);
      },
    );

    test(
      'flag ON: a member matched only by a switch-expression arm is '
      'reported but report-only (removal blocked, no coupled arms)',
      () async {
        final result = await runUnions(flag: true);
        final decl = findByName(result, 'ExpressionOnlySignal');
        expect(decl, isNotNull);
        expect(decl!.removalBlocked, isTrue);
        expect(decl.coupledRemovals, isEmpty);
      },
    );

    test('flag ON: a member matched only by an if-case is reported but '
        'report-only (removal blocked, no coupled arms)', () async {
      final result = await runUnions(flag: true);
      final decl = findByName(result, 'IfCaseOnlySignal');
      expect(decl, isNotNull, reason: 'still reported as dead');
      expect(decl!.removalBlocked, isTrue);
      // Nothing is coupled: `--unused-union-members` never removes arms.
      expect(decl.coupledRemovals, isEmpty);
    });

    test('flag ON: a member that is also constructed is never flagged, nor is '
        'the sealed supertype', () async {
      final names = qualifiedNames((await runUnions(flag: true)).unused);
      // LiveSignal has a real, non-pattern reference (construction) -> alive.
      expect(names, isNot(contains('LiveSignal')));
      // Signal appears as a parameter/scrutinee type -> a real use.
      expect(names, isNot(contains('Signal')));
    });

    test('flag OFF: every pattern-matched member counts as used (Phase 1 '
        'behavior is unchanged)', () async {
      final names = qualifiedNames((await runUnions(flag: false)).unused);
      expect(names, isNot(contains('StatementOnlySignal')));
      expect(names, isNot(contains('ExpressionOnlySignal')));
      expect(names, isNot(contains('IfCaseOnlySignal')));
      expect(names, isNot(contains('LiveSignal')));
      expect(names, isNot(contains('Signal')));
    });
  });
}
