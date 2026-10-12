@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('entry points', () {
    Future<FinderResult> runEntryPoints({
      List<EntryPoint> entryPoints = const [],
    }) => runScenario([
      'lib/scenarios/entry_points.dart',
      'lib/scenarios/entry_points/**',
      'test/**',
    ], entryPoints: entryPoints);

    /// `path:qualifiedName`, since the fixture has two `testExecutable`s.
    Set<String> located(FinderResult result) => {
      for (final d in result.unused) '${d.filePath}:${d.qualifiedName}',
    };

    test('exempts a declaration by file and name only', () async {
      expect(located(await runEntryPoints()), {
        // Wrong file.
        'lib/scenarios/entry_points.dart:testExecutable',
        'lib/scenarios/entry_points.dart:integrationMain',
        'lib/scenarios/entry_points.dart:Plugin',
        'lib/scenarios/entry_points.dart:Plugin.registerWith',
        'lib/scenarios/entry_points.dart:Plugin.other',
        'lib/scenarios/entry_points.dart:bootstrap',
        // The right file exempts `testExecutable` whatever its shape, and
        // nothing beside it.
        'lib/scenarios/entry_points/flutter_test_config.dart:deadHelperNextToConfig',
      });
    });

    test(
      'a project lists its own, by file and name, member, or bare name',
      () async {
        final result = await runEntryPoints(
          entryPoints: [
            .fromConfig(
              'integrationMain',
              files: ['lib/scenarios/entry_points.dart'],
            ),
            .fromConfig('Plugin.registerWith', files: ['**/entry_points.dart']),
            .fromConfig('bootstrap'),
          ],
        );

        expect(located(result), {
          'lib/scenarios/entry_points.dart:testExecutable',
          // The member rule keeps the type it lives in — the generated call
          // names it too — but not the type's other members.
          'lib/scenarios/entry_points.dart:Plugin.other',
          'lib/scenarios/entry_points/flutter_test_config.dart:deadHelperNextToConfig',
        });
      },
    );

    test(
      'a project rule whose globs match no scanned file changes nothing',
      () async {
        final result = await runEntryPoints(
          entryPoints: [
            .fromConfig('bootstrap', files: ['bin/**']),
          ],
        );
        expect(
          located(result),
          contains('lib/scenarios/entry_points.dart:bootstrap'),
        );
      },
    );

    test('narrates each skipped entry point other than main', () async {
      final lines = <String>[];
      final level = Logger.root.level;
      Logger.root.level = .FINE;
      final logging = Logger.root.onRecord
          .where((r) => r.loggerName == 'ciach.finder')
          .listen((r) => lines.add(r.message));
      addTearDown(() {
        Logger.root.level = level;
        return logging.cancel();
      });
      await runEntryPoints(
        entryPoints: [
          .fromConfig('bootstrap'),
          .fromConfig('Plugin.registerWith'),
        ],
      );

      final skipped = lines.where((l) => l.startsWith('Skipped ')).toList();
      const plugin =
          'Skipped lib/scenarios/entry_points.dart:15 Plugin: declares the entry point Plugin.registerWith.';
      const registerWith =
          'Skipped lib/scenarios/entry_points.dart:16 Plugin.registerWith: '
          'listed under `entry-points` in the config file.';
      const bootstrap =
          'Skipped lib/scenarios/entry_points.dart:21 bootstrap: listed under `entry-points` in the config file.';
      const byShape =
          'Skipped lib/scenarios/entry_points/flutter_test_config.dart:4 '
          'testExecutable: called by the `flutter test` bootstrap.';
      const real =
          'Skipped test/flutter_test_config.dart:6 testExecutable: called by the `flutter test` bootstrap.';
      expect(skipped, [plugin, registerWith, bootstrap, byShape, real]);
      expect(lines, isNot(contains(contains(' main:'))));
    });
  });
}
