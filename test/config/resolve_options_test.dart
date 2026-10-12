import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/config.dart';

void main() {
  group('resolveOptions', () {
    test('falls back to the built-in defaults with no config and no args', () {
      final resolved = resolve(const []);

      expect(resolved.rootPath, '.');
      expect(resolved.includePublic, isTrue);
      expect(resolved.includeExported, isTrue);
      expect(resolved.includeGenerated, isFalse);
      expect(resolved.projectConfig, isTrue);
      expect(resolved.unusedTranslations, isFalse);
      expect(resolved.overrides, isFalse);
      expect(resolved.operators, isFalse);
      expect(resolved.unusedUnionMembers, isFalse);
      expect(resolved.reportToJson, isFalse);
      expect(resolved.transitive, isFalse);
      expect(resolved.setExitIfChanged, isFalse);
      expect(resolved.remove, isFalse);
      expect(resolved.force, isFalse);
      expect(resolved.includeGlobs, isEmpty);
      expect(resolved.excludeGlobs, isEmpty);
      expect(resolved.additionalGeneratedSuffixes, isEmpty);
      expect(resolved.additionalGeneratedGlobs, isEmpty);
      expect(resolved.kinds, FinderOptions.defaultKinds);
      expect(resolved.format, 'text');
      expect(resolved.verbose, isFalse);
      expect(resolved.concurrency, 16);
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
concurrency: 4
dart: /sdk/bin/dart
''', origin: 'ciach.yaml');

      final resolved = resolve(const [
        '--public',
        '--no-generated',
        '--format',
        'github',
        '--color',
        '--progress',
        '--concurrency',
        '2',
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
      expect(resolved.concurrency, 2);
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
        '--generated-suffix',
        '.gc.dart',
        '--generated-suffix',
        '.pb.dart',
        '--generated-glob',
        'lib/l10n/**',
        '--generated-glob',
        'third_party/**',
      ]);

      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart', '.pb.dart']);
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

    test('rejects a non-positive --concurrency', () {
      for (final value in ['0', '-1']) {
        expect(
          () => resolve(['--concurrency', value]),
          throwsA(aUsageException(contains('below the minimum (1)'))),
          reason: 'for --concurrency $value',
        );
      }
      expect(
        () => resolve(const ['--concurrency', 'lots']),
        throwsA(aUsageException(contains('lots'))),
      );
    });

    test('rejects an unknown --kinds value', () {
      expect(
        () => resolve(const ['-k', 'klass']),
        throwsA(aUsageException(contains("Unknown kind 'klass'"))),
      );
    });

    test('reports every problem at once, not just the first', () {
      // An out-of-range `--format` is not among them: an option's `allowed`
      // list is the arg parser's business, so that fails before resolution.
      expect(
        () => resolve(const ['-k', 'klass', '-j', '0']),
        throwsA(
          aUsageException(
            allOf(
              contains("Unknown kind 'klass'"),
              contains('below the minimum (1)'),
            ),
          ),
        ),
      );
    });

    test('hands the finder its share of the settings', () {
      final resolved = resolve(const [
        '--no-public',
        '--no-project-config',
        '--overrides',
        '-e',
        'test/**',
        '-j',
        '4',
      ], .parse('entry-points: [{name: bootstrap}]', origin: 'ciach.yaml'));
      final options = resolved.finderOptions();

      expect(options.rootPath, p.normalize(p.absolute('.')));
      expect(options.includePublic, isFalse);
      // Inverted for the finder.
      expect(options.skipOverrides, isFalse);
      expect(options.skipOperators, isTrue);
      expect(options.excludeGlobs, ['test/**']);
      expect(options.entryPoints.map((e) => '$e'), ['bootstrap']);
      expect(options.concurrency, 4);
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
        options.entryPoints.map((e) => e.name),
        containsAllInOrder(['bootstrap', 'onRequest']),
      );
      expect(options.additionalGeneratedGlobs, [
        'gen/**',
        'lib/l10n/app_localizations_*.dart',
        'lib/l10n/app_localizations.dart',
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
