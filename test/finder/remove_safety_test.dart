@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('remove-safety guards', () {
    // Scan only the guard fixture; its declarations are self-contained (kept
    // alive by in-file type references), so no cross-file setup is needed.
    Future<FinderResult> runGuards() =>
        runScenario(['lib/scenarios/guards.dart']);

    test(
      'emptying a still-referenced enum is reported but removal-blocked',
      () async {
        final result = await runGuards();
        // No value is named individually and `.values` is never iterated, but
        // the enum TYPE stays referenced, so the empty-enum guard blocks removal
        // instead of emptying the enum. (Enums reached via `.values` are
        // instead treated as used and never reported — see the `enum `.values`
        // detection fix` group.)
        for (final qualified in const [
          'EmptyableStatus.pending',
          'EmptyableStatus.settled',
        ]) {
          final decl = findByQualified(result, qualified);
          expect(decl, isNotNull, reason: '$qualified should be flagged dead');
          // Removing every value would leave `enum EmptyableStatus {}`, so the
          // finding is surfaced but --remove must leave it in place.
          expect(
            decl!.removalBlocked,
            isTrue,
            reason: '$qualified would empty a still-referenced enum',
          );
        }
      },
    );

    test(
      'the sole constructor of a live class with final fields is reported but '
      'removal-blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'LabeledBox.new');
        expect(decl, isNotNull, reason: 'the dead constructor is still a find');
        expect(decl!.kind, SymbolKind.constructor);
        // Removing it would strand the `final label` field, so block removal.
        expect(decl.removalBlocked, isTrue);
      },
    );

    test(
      'a super-forwarding sole constructor is reported but removal-blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'ForwardingChild.new');
        expect(decl, isNotNull);
        expect(decl!.kind, SymbolKind.constructor);
        // Removing it would leave an implicit default constructor calling a
        // non-existent zero-arg `super()`, so block removal.
        expect(decl.removalBlocked, isTrue);
      },
    );

    test(
      'a safe sole-constructor removal (no final fields, no super forwarding) '
      'is reported and NOT blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'MutableBag.new');
        expect(decl, isNotNull, reason: 'still a real unused finding');
        // Nothing to strand and no super to break: safe to auto-remove.
        expect(
          decl!.removalBlocked,
          isFalse,
          reason: 'no final fields and no super forwarding',
        );
      },
    );
  });
}
