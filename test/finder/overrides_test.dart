@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('dead members with overrides', () {
    // The fixture's types are kept alive from bin/app.dart.
    Future<FinderResult> runOverrides({bool withImplFile = true}) =>
        runScenario([
          'lib/scenarios/overrides.dart',
          if (withImplFile) 'lib/scenarios/overrides_impl.dart',
        ]);

    UnusedDeclaration finding(FinderResult result, String name) =>
        result.unused.firstWhere((d) => d.qualifiedName == name);

    test('couples every override of a dead member to its removal', () async {
      final result = await runOverrides();
      final prime = finding(result, 'Pump.prime');
      expect(prime.removalBlocked, isFalse);
      // `Piston.prime`, and `Turbine.prime` two levels down.
      expect(prime.coupledRemovals, hasLength(2));
      final names = qualifiedNames(result.unused);
      expect(names, isNot(contains('Piston.prime')));
      expect(names, isNot(contains('Turbine.prime')));
    });

    test('a call to an override keeps the member it overrides', () async {
      // Why an override needs no reference check of its own: the server
      // answers every member of an override family with the same references.
      final names = (await runOverrides()).unused.map((d) => d.qualifiedName);
      expect(names, isNot(contains('Faucet.drip')));
      expect(names, isNot(contains('Tap.drip')));
    });

    test('couples an override that lives in another file', () async {
      final close = finding(await runOverrides(), 'Valve.close');
      expect(close.removalBlocked, isFalse);
      expect(
        close.coupledRemovals.single.filePath,
        'lib/scenarios/overrides_impl.dart',
      );
    });

    test('keeps a member whose override is in an unscanned file', () async {
      final close = finding(
        await runOverrides(withImplFile: false),
        'Valve.close',
      );
      expect(close.removalBlocked, isTrue);
      expect(close.coupledRemovals, isEmpty);
      expect(close.hint, contains('overridden'));
    });

    test('couples an override declared as a plain field', () async {
      final reading = finding(await runOverrides(), 'Gauge.reading');
      expect(reading.removalBlocked, isFalse);
      expect(reading.coupledRemovals, hasLength(1));
    });

    test('keeps a member whose override is a declaring parameter', () async {
      final rating = finding(await runOverrides(), 'Rated.rating');
      expect(rating.removalBlocked, isTrue);
      expect(rating.coupledRemovals, isEmpty);
    });

    test('couples an override sharing a field statement', () async {
      // `final int left = 1, right = 2;` — each declarator is coupled as a
      // field, so the remover takes the statement whole once both are gone.
      final result = await runOverrides();
      for (final name in ['Paired.left', 'Paired.right']) {
        final declarator = finding(result, name);
        expect(declarator.removalBlocked, isFalse, reason: name);
        expect(
          declarator.coupledRemovals.single.kind,
          SymbolKind.field,
          reason: name,
        );
      }
      // Both are overrides, including the one with no annotation of its own.
      final names = qualifiedNames(result.unused);
      expect(names, isNot(contains('Pair.left')));
      expect(names, isNot(contains('Pair.right')));
    });

    test(
      'couples one declarator and keeps the rest of the statement',
      () async {
        // Only `dead` implements a dead member, so the statement survives.
        final result = await runOverrides();
        final dead = finding(result, 'Halved.dead');
        expect(dead.removalBlocked, isFalse);
        expect(dead.coupledRemovals.single.kind, SymbolKind.field);
        final names = qualifiedNames(result.unused);
        expect(names, isNot(contains('Halved.live')));
        expect(names, isNot(contains('Mixed.live')));
      },
    );

    test('never reports a member called through the interface', () async {
      final names = qualifiedNames((await runOverrides()).unused);
      expect(names, isNot(contains('Pump.start')));
      expect(names, isNot(contains('Piston.start')));
    });

    test('couples the override of a dead method in the default run', () async {
      // `Dog.sound` overrides the dead `Animal.sound`; `--remove` takes both.
      final sound = finding(await runFinder(), 'Animal.sound');
      expect(sound.removalBlocked, isFalse);
      expect(sound.coupledRemovals, hasLength(1));
    });
  });
}
