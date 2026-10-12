@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('cross-library reference recovery', () {
    // The consumer file must be scanned too, or the recovery can't see the
    // usage sites the reference index misses.
    Future<FinderResult> runXrefResult() => runScenario(const [
      'lib/scenarios/xref_shapes.dart',
      'lib/scenarios/xref_event.dart',
      'lib/scenarios/xref_analytics.dart',
      'lib/scenarios/xref_uses.dart',
      'lib/scenarios/xref_surface.dart',
    ]);

    Future<Set<String>> runXref() async =>
        qualifiedNames((await runXrefResult()).unused);

    test('a getter/field used only by a cross-file object pattern is not '
        'flagged', () async {
      final names = await runXref();
      expect(names, isNot(contains('XrefLoadedState.hasActive')));
      expect(names, isNot(contains('XrefLoadedState.ready')));
    });

    test(
      'a same-file object-pattern reference still keeps a getter alive',
      () async {
        expect(await runXref(), isNot(contains('XrefLoadedState.localFlag')));
      },
    );

    test(
      'an enum value used only via a cross-library dot-shorthand is not flagged',
      () async {
        expect(await runXref(), isNot(contains('XrefEvent.signOut')));
      },
    );

    test('a member used only through an override from a file that does not '
        'import it is not flagged', () async {
      final result = await runXrefResult();
      final names = qualifiedNames(result.unused);
      expect(names, isNot(contains('XrefSurface.glossy')));
      expect(names, contains('XrefSurface.matte'));
      final glossy = result.recoveredReferences.firstWhere(
        (w) => w.qualifiedName == 'XrefSurface.glossy',
      );
      expect(glossy.usageFilePath, endsWith('xref_uses.dart'));
    });

    test('a normally-referenced enum value is not flagged', () async {
      expect(await runXref(), isNot(contains('XrefEvent.signIn')));
    });

    test(
      'genuinely-dead members are still flagged — the recovery did not blind '
      'the detector',
      () async {
        final names = await runXref();
        expect(names, contains('XrefLoadedState.deadShapeGetter'));
        expect(names, contains('XrefEvent.deadEvent'));
      },
    );

    test('each recovered reference is surfaced as a warning; normal and '
        'genuinely-dead declarations are not', () async {
      final result = await runXrefResult();
      final warned = result.recoveredReferences
          .map((w) => w.qualifiedName)
          .toSet();
      // Confirmed used by the secondary check.
      expect(
        warned,
        containsAll([
          'XrefLoadedState.hasActive',
          'XrefLoadedState.ready',
          'XrefEvent.signOut',
        ]),
      );
      // Normally referenced -> not recovered, no warning.
      expect(warned, isNot(contains('XrefEvent.signIn')));
      expect(warned, isNot(contains('XrefLoadedState.localFlag')));
      // Genuinely dead -> stays a finding, not a warning.
      expect(warned, isNot(contains('XrefLoadedState.deadShapeGetter')));
      expect(warned, isNot(contains('XrefEvent.deadEvent')));
      // The warning carries the confirmed usage location and the hedge.
      final signOut = result.recoveredReferences.firstWhere(
        (w) => w.qualifiedName == 'XrefEvent.signOut',
      );
      expect(signOut.usageFilePath, endsWith('xref_uses.dart'));
      expect(signOut.message, contains('likely a Dart SDK find-references'));
    });
  });

  test('transitive: a recovered member with a dead and a live use stays '
      'used', () async {
    final result = await runScenario(const [
      'lib/scenarios/xref_shapes.dart',
      'lib/scenarios/xref_surface.dart',
      'lib/scenarios/xref_dead_cycles.dart',
    ], transitive: true);
    final names = qualifiedNames(result.unused);
    expect(names, contains('_deadReady'));
    expect(names, isNot(contains('XrefLoadedState.ready')));
    expect(names, isNot(contains('liveReady')));
  });

  test('a top-level getter named in a show combinator is used', () async {
    final result = await runScenario(const [
      'lib/scenarios/show_combinator*.dart',
    ]);
    final unused = qualifiedNames(result.unused);
    final recovered = result.recoveredReferences
        .map((w) => w.qualifiedName)
        .toSet();

    expect(unused, contains('deadUnshownGetter'));
    expect(unused, isNot(contains('liveShownGetter')));
    expect(recovered, contains('liveShownGetter'));
  });

  group('same-simple-name collision recovery', () {
    // Two members share the simple name `status`: one used only from another
    // file (must be recovered) and one never used (must stay flagged). Guards
    // the definition position-matching that tells them apart.
    Future<FinderResult> runCollision() => runScenario(const [
      'lib/scenarios/xref_collision.dart',
      'lib/scenarios/xref_collision_uses.dart',
    ]);

    test(
      'recovers the used member and still flags the dead namesake',
      () async {
        final result = await runCollision();
        final unused = qualifiedNames(result.unused);
        final warned = result.recoveredReferences
            .map((w) => w.qualifiedName)
            .toSet();
        // The genuinely-dead namesake is still reported.
        expect(unused, contains('DeadState.status'));
        // The used-only-cross-file namesake is recovered, not reported.
        expect(unused, isNot(contains('LiveState.status')));
        expect(warned, contains('LiveState.status'));
        expect(warned, isNot(contains('DeadState.status')));
      },
    );
  });
}
