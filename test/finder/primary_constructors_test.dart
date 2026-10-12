@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('primary constructors (Dart 3.13)', () {
    Future<FinderResult> runPrimary() =>
        runScenario(['lib/scenarios/primary_constructors.dart']);

    test("reports exactly the fixture's dead declarations", () async {
      final result = await runPrimary();
      expect(qualifiedNames(result.unused), {
        'Suit.spades',
        'DeadPoint',
        'Registry.deadNamed',
        'Registry.deadFactory',
        'Registry.deadRedirect',
        'Registry.deadCounter',
        // Declaring parameters: positional, named, optional positional.
        'Endpoint.port',
        'Chip.badge',
        'Ranged.high',
        'Secret.seed',
        // The fixture's own entry points, called by nothing in the scan.
        'usePrimaryConstructors',
        'useSecretType',
      });
    });

    test("a primary constructor's body part is never a finding of its own", () {
      // The server reports `this : assert(…);` as a constructor named `this`.
      return expectLater(
        runPrimary().then((r) => r.unused.map((d) => d.qualifiedName)),
        completion(isNot(contains(anyOf('Delta.this', 'Delta.new')))),
      );
    });

    test(
      'a dead declaring parameter is reported but removal-blocked',
      () async {
        final result = await runPrimary();
        // A parameter group's own brackets must not be taken for the body.
        for (final qualified in const [
          'Endpoint.port',
          'Chip.badge',
          'Ranged.high',
        ]) {
          final decl = findByQualified(result, qualified);
          expect(decl, isNotNull, reason: 'nothing ever reads $qualified');
          expect(decl!.kind, SymbolKind.field);
          expect(decl.removalBlocked, isTrue);
          expect(decl.hint, contains('declaring parameter'));
        }
      },
    );

    test('a dead class takes its header declarations with it', () async {
      final result = await runPrimary();
      final decl = findByQualified(result, 'DeadPoint');
      expect(decl, isNotNull);
      expect(decl!.kind, SymbolKind.class$);
      expect(decl.removalBlocked, isFalse);
      for (final qualified in const ['DeadPoint.x', 'DeadPoint.y']) {
        expect(findByQualified(result, qualified), isNull);
      }
    });

    test('abbreviated `new`/`factory` constructors stay removable', () async {
      final result = await runPrimary();
      for (final qualified in const [
        'Registry.deadNamed',
        'Registry.deadFactory',
        'Registry.deadRedirect',
      ]) {
        final decl = findByQualified(result, qualified);
        expect(decl, isNotNull, reason: '$qualified is never invoked');
        expect(decl!.kind, SymbolKind.constructor);
        expect(
          decl.removalBlocked,
          isFalse,
          reason: '$qualified is a body member',
        );
      }
    });

    test('a primary constructor asked for on its own is report-only', () async {
      // Without class candidates to absorb it, a dead class's header
      // constructor is reported on its own.
      final result = await runScenario(
        ['lib/scenarios/primary_constructors.dart'],
        kinds: const {.constructor},
      );
      final decl = findByQualified(result, 'DeadPoint.new');
      expect(decl, isNotNull, reason: '`DeadPoint` is never constructed');
      expect(decl!.removalBlocked, isTrue);
      expect(decl.hint, contains('primary constructor'));
      expect(findByQualified(result, 'Point.new'), isNull);
      // A query at the header resolves to the class, so `Secret._` inherits the
      // references of a class that is still used as a type.
      expect(findByQualified(result, 'Secret._'), isNull);
    });
  });
}
