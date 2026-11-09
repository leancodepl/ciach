/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/ci.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_options.dart';

void main() {
  group('resolveOptions', () {
    test('falls back to the built-in defaults with no config and no args', () {
      final resolved = resolve(const []);

      expect(resolved.rootPath, '.');
      expect(resolved.includePublic, isTrue);
      expect(resolved.exportedPackages, isEmpty);
      expect(resolved.includeGenerated, isFalse);
      expect(resolved.projectConfig, isTrue);
      expect(resolved.unusedTranslations, isTrue);
      expect(resolved.overrides, isFalse);
      expect(resolved.unusedUnionMembers, isFalse);
      expect(resolved.reportToJson, isFalse);
      expect(resolved.transitive, isTrue);
      expect(resolved.setExitIfChanged, isFalse);
      expect(resolved.remove, isFalse);
      expect(resolved.force, isFalse);
      expect(resolved.includeGlobs, isEmpty);
      expect(resolved.excludeGlobs, isEmpty);
      expect(resolved.additionalGeneratedGlobs, isEmpty);
      expect(resolved.kinds, FinderOptions.defaultKinds);
      expect(resolved.format, 'text');
      expect(resolved.verbose, isFalse);
      expect(resolved.dartExecutable, isNull);
    });

    test('command-line flags override the config', () {
      final config = ConfigFile.parse('''
path: packages/app
public: false
generated: true
format: json
color: false
progress: false
dart: /sdk/bin/dart
''', origin: 'ciach.yaml');

      final resolved = resolve(const [
        '--public',
        '--no-generated',
        '--format',
        'github',
        '--color',
        '--progress',
        '--dart',
        '/other/dart',
        'packages/other',
      ], config);

      expect(resolved.rootPath, 'packages/other');
      expect(resolved.includePublic, isTrue);
      expect(resolved.includeGenerated, isFalse);
      expect(resolved.format, 'github');
      expect(resolved.color, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.dartExecutable, '/other/dart');
    });

    test('a command-line list replaces the config list, not appends', () {
      final config = ConfigFile.parse(
        "exclude: ['test/**']\nkinds: [class]",
        origin: 'ciach.yaml',
      );

      final resolved = resolve(const ['-e', 'tool/**', '-k', 'method'], config);

      expect(resolved.excludeGlobs, ['tool/**']);
      expect(resolved.kinds, <SymbolKind>{.method});
    });

    test('repeated command-line values all survive', () {
      final resolved = resolve(const [
        '-e',
        'test/**',
        '-e',
        'tool/**',
        '--generated-glob',
        'lib/l10n/**',
        '--generated-glob',
        'third_party/**',
      ]);

      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.additionalGeneratedGlobs, [
        'lib/l10n/**',
        'third_party/**',
      ]);
    });

    test('explicitly passing a flag at its default value still wins', () {
      // --public matches the default, so only the layer it came from tells it
      // apart from an absent flag — and it has to, to beat `public: false`.
      final resolved = resolve(const [
        '--public',
      ], .parse('public: false', origin: 'ciach.yaml'));

      expect(resolved.includePublic, isTrue);
    });

    test('auto-detected color and progress are the last resort', () {
      final auto = resolveWith(const [], const .empty(), progressDefault: true);
      // Each stream decides for itself.
      expect(auto.color, isNull);
      expect(auto.showProgress, isTrue);

      final fromConfig = resolveWith(
        const [],
        .parse('color: false\nprogress: false', origin: 'c.yaml'),
        progressDefault: true,
      );
      expect(fromConfig.color, isFalse);
      expect(fromConfig.showProgress, isFalse);

      final fromArgs = resolveWith(
        const ['--no-color', '--no-progress'],
        .parse('color: true\nprogress: true', origin: 'c.yaml'),
        progressDefault: true,
      );
      expect(fromArgs.color, isFalse);
      expect(fromArgs.showProgress, isFalse);
    });

    group('CI', () {
      test('turns on set-exit-if-changed and off progress', () {
        final local = resolveWith(
          const [],
          const .empty(),
          progressDefault: true,
        );
        expect(local.ci, isNull);
        expect(local.setExitIfChanged, isFalse);
        expect(local.verbose, isFalse);
        expect(local.showProgress, isTrue);
        expect(local.format, 'text');

        final onCi = resolveWith(
          const [],
          const .empty(),
          progressDefault: true,
          detectedCi: .gitlab,
        );
        expect(onCi.ci, CiRunner.gitlab);
        expect(onCi.setExitIfChanged, isTrue);
        expect(onCi.verbose, isTrue);
        expect(onCi.showProgress, isFalse);
        // GitLab has no annotation format.
        expect(onCi.format, 'text');
      });

      test('on GitHub Actions, the format defaults to github', () {
        final resolved = resolveWith(
          const [],
          const .empty(),
          progressDefault: false,
          detectedCi: .githubActions,
        );
        expect(resolved.format, 'github');
      });

      test('an explicit value beats the CI default', () {
        final fromArgs = resolveWith(
          const [
            '--no-set-exit-if-changed',
            '--no-verbose',
            '--progress',
            '-f',
            'json',
          ],
          const .empty(),
          progressDefault: false,
          detectedCi: .githubActions,
        );
        expect(fromArgs.ci, CiRunner.githubActions);
        expect(fromArgs.setExitIfChanged, isFalse);
        expect(fromArgs.verbose, isFalse);
        expect(fromArgs.showProgress, isTrue);
        expect(fromArgs.format, 'json');

        final fromConfig = resolveWith(
          const [],
          .parse('''
set-exit-if-changed: false
verbose: false
progress: true
format: text''', origin: 'c.yaml'),
          progressDefault: false,
          detectedCi: .githubActions,
        );
        expect(fromConfig.setExitIfChanged, isFalse);
        expect(fromConfig.verbose, isFalse);
        expect(fromConfig.showProgress, isTrue);
        expect(fromConfig.format, 'text');
      });

      test('--no-ci keeps the local defaults on a runner', () {
        for (final resolved in [
          resolveWith(
            const ['--no-ci'],
            const .empty(),
            progressDefault: true,
            detectedCi: .githubActions,
          ),
          resolveWith(
            const [],
            .parse('ci: false', origin: 'c.yaml'),
            progressDefault: true,
            detectedCi: .githubActions,
          ),
        ]) {
          expect(resolved.ci, isNull);
          expect(resolved.setExitIfChanged, isFalse);
          expect(resolved.verbose, isFalse);
          expect(resolved.showProgress, isTrue);
          expect(resolved.format, 'text');
        }
      });

      test('--ci applies the CI defaults anywhere', () {
        final forced = resolveWith(
          const ['--ci'],
          const .empty(),
          progressDefault: true,
        );
        expect(forced.ci, CiRunner.other);
        expect(forced.setExitIfChanged, isTrue);
        expect(forced.verbose, isTrue);
        expect(forced.showProgress, isFalse);
        expect(forced.format, 'text');

        // On a known service, --ci only confirms it.
        final confirmed = resolveWith(
          const ['--ci'],
          const .empty(),
          progressDefault: false,
          detectedCi: .githubActions,
        );
        expect(confirmed.ci, CiRunner.githubActions);
        expect(confirmed.format, 'github');

        // The command line beats a config file's opt-out.
        expect(
          resolveWith(
            const ['--ci'],
            .parse('ci: false', origin: 'c.yaml'),
            progressDefault: false,
            detectedCi: .githubActions,
          ).ci,
          CiRunner.githubActions,
        );
      });
    });

    test('verbose comes from the command line or the config', () {
      expect(resolve(const ['--verbose']).verbose, isTrue);
      expect(resolve(const ['-v']).verbose, isTrue);
      expect(resolveFile('verbose: true').verbose, isTrue);
      expect(
        resolve(const [
          '--no-verbose',
        ], .parse('verbose: true', origin: 'c.yaml')).verbose,
        isFalse,
      );
    });

    test('verbose supersedes the progress line', () {
      // Both write to stderr, so verbose wins however progress was asked for.
      expect(
        resolveWith(
          const ['--verbose', '--progress'],
          const .empty(),
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      expect(
        resolveWith(
          const [],
          .parse('verbose: true\nprogress: true', origin: 'c.yaml'),
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      expect(
        resolveWith(
          const ['--progress'],
          .parse('verbose: true', origin: 'c.yaml'),
          progressDefault: false,
        ).showProgress,
        isFalse,
      );
      // …but progress still works when verbose is off.
      expect(resolve(const ['--progress']).showProgress, isTrue);
    });

    test('rejects an unknown --kinds value', () {
      expect(
        () => resolve(const ['-k', 'klass']),
        throwsA(isUsageException(contains("Unknown kind 'klass'"))),
      );
    });

    test('rejects the removed `--kinds` value `constant`', () {
      expect(
        () => resolve(const ['-k', 'class,constant']),
        throwsA(
          isUsageException(
            contains(
              '`constant` was removed: ciach reports a `const` variable as a `variable` or a `field`, so use those.',
            ),
          ),
        ),
      );
    });

    test('reports every problem at once, not just the first', () {
      // An out-of-range `--format` is not among them: an option's `allowed`
      // list is the arg parser's business, so that fails before resolution.
      expect(
        () => resolve(const [
          '-k',
          'klass',
        ], .parse('also: [override]', origin: 'ciach.yaml')),
        throwsA(
          isUsageException(
            allOf(
              contains("Unknown kind 'klass'"),
              contains("Unknown value 'override' for `also`."),
            ),
          ),
        ),
      );
    });

    test('hands the finder its share of the settings', () {
      final resolved = resolve(const [
        '--no-public',
        '--no-project-config',
        '--also',
        'overrides',
        '-e',
        'test/**',
      ], .parse('entry-points: [{name: bootstrap}]', origin: 'ciach.yaml'));
      final options = resolved.finderOptions();

      expect(options.rootPath, p.normalize(p.absolute('.')));
      expect(options.includePublic, isFalse);
      // Inverted for the finder.
      expect(options.skipOverrides, isFalse);
      expect(options.excludeGlobs, ['test/**']);
      expect(options.entryPoints.map((e) => '$e'), ['bootstrap']);
    });
  });

  group('project config', () {
    late Directory package;

    setUp(() {
      package = .systemTemp.createTempSync('ciach_config_project_');
      File(p.join(package.path, 'pubspec.yaml')).writeAsStringSync('''
name: server
dependencies:
  dart_frog: any
  serverpod: any
''');
      File(p.join(package.path, 'l10n.yaml')).writeAsStringSync('');
    });

    tearDown(() => package.deleteSync(recursive: true));

    test('is merged into the finder options', () {
      final options = resolve(
        [package.path, '--generated-glob', 'gen/**'],
        .parse('entry-points: [{name: bootstrap}]', origin: 'ciach.yaml'),
      ).finderOptions();

      expect(
        options.entryPoints.map((e) => e.label),
        containsAllInOrder(['bootstrap', 'onRequest']),
      );
      // The template is scanned for unused messages, so it isn't generated.
      expect(options.additionalGeneratedGlobs, [
        'gen/**',
        'lib/l10n/app_localizations_*.dart',
      ]);
    });

    test('--no-project-config reads none of it', () {
      final options = resolve([
        package.path,
        '--no-project-config',
      ]).finderOptions();

      expect(options.entryPoints, isEmpty);
      expect(options.additionalGeneratedGlobs, isEmpty);
    });
  });
}
