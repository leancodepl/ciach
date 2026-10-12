@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/finder.dart';
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('freezed union deserialization-only arms', () {
    // Whole-package analysis still resolves the cross-file `Base.fromJson` use.
    Future<Set<String>> runFreezedUnions() async {
      final result = await runScenario(const [
        'lib/scenarios/freezed_unions.dart',
      ]);
      return qualifiedNames(result.unused);
    }

    test('a redirecting-factory arm of a @Freezed union with a referenced '
        'fromJson is treated as used (was a false positive)', () async {
      final names = await runFreezedUnions();
      // Built only by the generated fromJson, never hand-called.
      expect(names, isNot(contains('Base.contestEvent')));
      expect(names, isNot(contains('Base.matchEvent')));
    });

    test('arms of a @freezed union with NO fromJson stay flagged', () async {
      final names = await runFreezedUnions();
      // `Standalone` is never deserialized, so its arms are genuinely dead.
      expect(names, contains('Standalone.left'));
      expect(names, contains('Standalone.right'));
    });

    test(
      'a redirecting factory on a NON-annotated class stays flagged',
      () async {
        final names = await runFreezedUnions();
        // The fix only exempts `@freezed`/`@Freezed` unions.
        expect(names, contains('Plain.make'));
      },
    );

    test(
      'a never-dispatched arm of a deserialized union is also suppressed '
      '(documented over-suppression: indistinguishable from a live arm)',
      () async {
        final names = await runFreezedUnions();
        // Genuinely dead, but statically indistinguishable from a live deser-only arm.
        expect(names, isNot(contains('Base.deadArm')));
      },
    );
  });

  group('toJson/fromJson serialization hooks', () {
    // Whole-package analysis still resolves the cross-file uses from bin/app.dart.
    Future<Set<String>> runSerialization({bool reportToJson = false}) async {
      final result = await Ciach(
        .new(
          rootPath: fixturePath,
          includeGlobs: const ['lib/scenarios/serialization.dart'],
          reportToJson: reportToJson,
        ),
      ).run();
      return qualifiedNames(result.unused);
    }

    test('a toJson() is exempt by convention, for any class, annotated or '
        'not — jsonEncode can call it invisibly', () async {
      final names = await runSerialization();
      expect(names, isNot(contains('Plain.toJson')));
      expect(names, isNot(contains('Profile.toJson')));
    });

    test('a toJson() returning a non-Map JSON value — a List or a primitive — '
        'is exempt too, since those are valid json values', () async {
      final names = await runSerialization();
      expect(names, isNot(contains('Listy.toJson')));
      expect(names, isNot(contains('Stringy.toJson')));
    });

    test('a toJson() returning an unrelated domain type is not a JSON hook, so '
        'an unused one stays flagged even without the flag', () async {
      expect(await runSerialization(), contains('Domainy.toJson'));
    });

    test(
      'an unused fromJson is still reported, even on an annotated type',
      () async {
        final names = await runSerialization();
        expect(names, contains('Plain.fromJson'));
        expect(names, contains('Profile.fromJson'));
        expect(names, contains('Point.fromJson'));
      },
    );

    test(
      'a toJson with a visible `.toJson()` caller is never flagged',
      () async {
        expect(await runSerialization(), isNot(contains('Visible.toJson')));
        expect(
          await runSerialization(reportToJson: true),
          isNot(contains('Visible.toJson')),
        );
      },
    );

    test('--report-tojson re-enables reporting a dead toJson', () async {
      final names = await runSerialization(reportToJson: true);
      expect(names, contains('Plain.toJson'));
      expect(names, contains('Profile.toJson'));
      // The non-Map JSON-value hooks re-appear under the flag as well.
      expect(names, contains('Listy.toJson'));
      expect(names, contains('Stringy.toJson'));
      // fromJson reporting is independent of the toJson flag.
      expect(names, contains('Plain.fromJson'));
    });
  });
}
