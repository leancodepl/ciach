import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final parser = buildParser();

  /// Resolves [arguments] against [config] with both auto-detected settings
  /// off, so only explicit values can turn them on.
  ResolvedOptions resolve(List<String> arguments, [CiachConfig? config]) =>
      resolveOptions(
        parser.parse(arguments),
        config ?? const CiachConfig(),
        colorDefault: false,
        progressDefault: false,
      );

  group('CiachConfig.parse', () {
    test('reads every option', () {
      final config = CiachConfig.parse('''
path: packages/app
public: false
generated: true
overrides: true
operators: true
unused-union-members: true
report-tojson: true
set-exit-if-changed: true
remove: true
force: true
exclude:
  - 'test/**'
  - 'tool/**'
include:
  - 'lib/**'
generated-suffix:
  - .gc.dart
kinds: [class, function]
format: github
color: false
progress: false
verbose: true
concurrency: 4
dart: /sdk/bin/dart
''', origin: 'ciach.yaml');

      expect(config.path, 'packages/app');
      expect(config.public, isFalse);
      expect(config.generated, isTrue);
      expect(config.overrides, isTrue);
      expect(config.operators, isTrue);
      expect(config.unusedUnionMembers, isTrue);
      expect(config.reportToJson, isTrue);
      expect(config.setExitIfChanged, isTrue);
      expect(config.remove, isTrue);
      expect(config.force, isTrue);
      expect(config.exclude, ['test/**', 'tool/**']);
      expect(config.include, ['lib/**']);
      expect(config.generatedSuffix, ['.gc.dart']);
      expect(config.kinds, ['class', 'function']);
      expect(config.format, 'github');
      expect(config.color, isFalse);
      expect(config.progress, isFalse);
      expect(config.verbose, isTrue);
      expect(config.concurrency, 4);
      expect(config.dart, '/sdk/bin/dart');
      // Every key that was in the file, and nothing else.
      expect(config.settings.keys, configKeys);
    });

    test('settings lists only what the file sets', () {
      final config = CiachConfig.parse('''
public: false
exclude: ['test/**']
concurrency: 4
''', origin: 'ciach.yaml');

      expect(config.settings, {
        'public': false,
        'exclude': ['test/**'],
        'concurrency': 4,
      });
    });

    test('covers every command-line option', () {
      // Guards the promise that anything settable on the command line is
      // settable in the file: every long option name (bar the config-file
      // plumbing and --help) must be a config key.
      final cliOnly = {'help', 'config', 'no-config'};
      final optionNames = parser.options.keys.toSet().difference(cliOnly);

      expect(configKeys.difference({'path'}), optionNames);
    });

    test('leaves unset options null', () {
      final config = CiachConfig.parse('public: false', origin: 'ciach.yaml');

      expect(config.public, isFalse);
      expect(config.format, isNull);
      expect(config.exclude, isNull);
      expect(config.concurrency, isNull);
    });

    test('treats an empty or comment-only file as no settings', () {
      for (final source in ['', '\n', '# nothing here\n']) {
        final config = CiachConfig.parse(source, origin: 'ciach.yaml');
        expect(config.public, isNull, reason: 'for ${source.trim()}');
      }
    });

    test('treats a valueless key as unset', () {
      final config = CiachConfig.parse('public:\n', origin: 'ciach.yaml');

      expect(config.public, isNull);
    });

    test('accepts a bare string where a list is expected', () {
      final config = CiachConfig.parse("exclude: 'test/**'", origin: 'c.yaml');

      expect(config.exclude, ['test/**']);
    });

    test('accepts comma-separated kinds in one string', () {
      final config = CiachConfig.parse('kinds: class,method', origin: 'c.yaml');

      expect(resolve(const [], config).kinds, <SymbolKind>{.class$, .method});
    });

    test('rejects an unknown option, naming the file and valid keys', () {
      expect(
        () => CiachConfig.parse('publik: false', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains("unknown option 'publik'")),
        ),
      );
    });

    test('rejects a top-level document that is not a map', () {
      expect(
        () => CiachConfig.parse('- public', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains('must be a map of options')),
        ),
      );
    });

    test('rejects malformed YAML', () {
      expect(
        () => CiachConfig.parse('public: [unclosed', origin: 'ciach.yaml'),
        throwsA(isFormatException('ciach.yaml', contains('not valid YAML'))),
      );
    });

    test('rejects a non-boolean flag', () {
      expect(
        () => CiachConfig.parse('public: sometimes', origin: 'ciach.yaml'),
        throwsA(
          isFormatException(
            'ciach.yaml',
            contains("'public' must be true or false, got a string"),
          ),
        ),
      );
    });

    test('rejects a non-string in a list', () {
      expect(
        () => CiachConfig.parse('exclude: [1]', origin: 'ciach.yaml'),
        throwsA(isFormatException('ciach.yaml', contains('a list of strings'))),
      );
    });

    test('rejects an unknown format', () {
      expect(
        () => CiachConfig.parse('format: xml', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains('text, json, github')),
        ),
      );
    });

    test('rejects an unknown kind', () {
      expect(
        () => CiachConfig.parse('kinds: [klass]', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains("Unknown kind 'klass'")),
        ),
      );
    });

    test('rejects a non-positive concurrency', () {
      for (final value in ['0', '-2', 'many', '1.5']) {
        expect(
          () => CiachConfig.parse('concurrency: $value', origin: 'c.yaml'),
          throwsA(isFormatException('c.yaml', contains('positive integer'))),
          reason: 'for concurrency: $value',
        );
      }
    });
  });

  group('loadConfig', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ciach_config_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    void write(String name, String content) =>
        File(p.join(tempDir.path, name)).writeAsStringSync(content);

    test('discovers ciach.yaml in the project directory', () {
      write('ciach.yaml', 'public: false');

      final loaded = loadConfig(projectDir: tempDir.path);

      expect(loaded.path, p.join(tempDir.path, 'ciach.yaml'));
      expect(loaded.config.public, isFalse);
    });

    test('discovers ciach.yaml only, not other spellings', () {
      write('ciach.yml', 'format: json');
      write('.ciach.yaml', 'format: json');

      expect(loadConfig(projectDir: tempDir.path).path, isNull);

      write('ciach.yaml', 'format: github');

      expect(loadConfig(projectDir: tempDir.path).config.format, 'github');
    });

    test('returns an empty config when the directory has none', () {
      final loaded = loadConfig(projectDir: tempDir.path);

      expect(loaded.path, isNull);
      expect(loaded.config.public, isNull);
    });

    test('does not look outside the project directory', () {
      write('ciach.yaml', 'public: false');
      final nested = Directory(p.join(tempDir.path, 'nested'))..createSync();

      expect(loadConfig(projectDir: nested.path).path, isNull);
    });

    test('loads an explicit path from outside the project directory', () {
      write('elsewhere.yaml', 'format: json');
      final nested = Directory(p.join(tempDir.path, 'nested'))..createSync();

      final loaded = loadConfig(
        projectDir: nested.path,
        explicitPath: p.join(tempDir.path, 'elsewhere.yaml'),
      );

      expect(loaded.config.format, 'json');
    });

    test('an explicit path wins over a discoverable file', () {
      write('ciach.yaml', 'format: github');
      write('other.yaml', 'format: json');

      final loaded = loadConfig(
        projectDir: tempDir.path,
        explicitPath: p.join(tempDir.path, 'other.yaml'),
      );

      expect(loaded.config.format, 'json');
    });

    test('reports a missing explicit path', () {
      expect(
        () => loadConfig(
          projectDir: tempDir.path,
          explicitPath: p.join(tempDir.path, 'nope.yaml'),
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('Config file does not exist'),
          ),
        ),
      );
    });

    test('ignore reads nothing, but still names the file it skipped', () {
      // Invalid on purpose: with --no-config it is never parsed, so a broken
      // config file can't fail a run that asked to ignore it.
      write('ciach.yaml', 'publik: [unclosed');

      final loaded = loadConfig(projectDir: tempDir.path, ignore: true);

      expect(loaded.ignored, isTrue);
      expect(loaded.path, p.join(tempDir.path, 'ciach.yaml'));
      expect(loaded.config.settings, isEmpty);
    });

    test('ignore reports no path when there was no config anyway', () {
      final loaded = loadConfig(projectDir: tempDir.path, ignore: true);

      expect(loaded.ignored, isTrue);
      expect(loaded.path, isNull);
    });

    test('ignore skips an explicit path, and its would-be errors', () {
      final loaded = loadConfig(
        projectDir: tempDir.path,
        explicitPath: p.join(tempDir.path, 'nope.yaml'),
        ignore: true,
      );

      expect(loaded.path, isNull);
    });
  });

  group('resolveOptions', () {
    test('falls back to the built-in defaults with no config and no args', () {
      final resolved = resolve(const []);

      expect(resolved.rootPath, '.');
      expect(resolved.includePublic, isTrue);
      expect(resolved.includeGenerated, isFalse);
      expect(resolved.overrides, isFalse);
      expect(resolved.operators, isFalse);
      expect(resolved.unusedUnionMembers, isFalse);
      expect(resolved.reportToJson, isFalse);
      expect(resolved.setExitIfChanged, isFalse);
      expect(resolved.remove, isFalse);
      expect(resolved.force, isFalse);
      expect(resolved.includeGlobs, isEmpty);
      expect(resolved.excludeGlobs, isEmpty);
      expect(resolved.additionalGeneratedSuffixes, isEmpty);
      expect(resolved.kinds, FinderOptions.defaultKinds);
      expect(resolved.format, 'text');
      expect(resolved.verbose, isFalse);
      expect(resolved.concurrency, 16);
      expect(resolved.dartExecutable, isNull);
    });

    test('takes config values when the command line is silent', () {
      final resolved = resolve(
        const [],
        const CiachConfig(
          path: 'packages/app',
          public: false,
          generated: true,
          overrides: true,
          operators: true,
          unusedUnionMembers: true,
          reportToJson: true,
          setExitIfChanged: true,
          remove: true,
          force: true,
          exclude: ['test/**'],
          include: ['lib/**'],
          generatedSuffix: ['.gc.dart'],
          kinds: ['class'],
          format: 'json',
          color: true,
          progress: true,
          concurrency: 4,
          dart: '/sdk/bin/dart',
        ),
      );

      expect(resolved.rootPath, 'packages/app');
      expect(resolved.includePublic, isFalse);
      expect(resolved.includeGenerated, isTrue);
      expect(resolved.overrides, isTrue);
      expect(resolved.operators, isTrue);
      expect(resolved.unusedUnionMembers, isTrue);
      expect(resolved.reportToJson, isTrue);
      expect(resolved.setExitIfChanged, isTrue);
      expect(resolved.remove, isTrue);
      expect(resolved.force, isTrue);
      expect(resolved.excludeGlobs, ['test/**']);
      expect(resolved.includeGlobs, ['lib/**']);
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart']);
      expect(resolved.kinds, {SymbolKind.class$});
      expect(resolved.format, 'json');
      expect(resolved.useColor, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.concurrency, 4);
      expect(resolved.dartExecutable, '/sdk/bin/dart');
    });

    test('command-line flags override the config', () {
      const config = CiachConfig(
        path: 'packages/app',
        public: false,
        generated: true,
        format: 'json',
        color: false,
        progress: false,
        concurrency: 4,
        dart: '/sdk/bin/dart',
      );

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
      expect(resolved.useColor, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.concurrency, 2);
      expect(resolved.dartExecutable, '/other/dart');
    });

    test('a command-line list replaces the config list, not appends', () {
      const config = CiachConfig(exclude: ['test/**'], kinds: ['class']);

      final resolved = resolve(const ['-e', 'tool/**', '-k', 'method'], config);

      expect(resolved.excludeGlobs, ['tool/**']);
      expect(resolved.kinds, {SymbolKind.method});
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
      ]);

      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart', '.pb.dart']);
    });

    test('explicitly passing a flag at its default value still wins', () {
      // --public matches the built-in default, so only `wasParsed` can tell it
      // apart from an absent flag — and it has to, to beat `public: false`.
      final resolved = resolve(const [
        '--public',
      ], const CiachConfig(public: false));

      expect(resolved.includePublic, isTrue);
    });

    test('auto-detected color and progress are the last resort', () {
      final auto = resolveOptions(
        parser.parse(const []),
        const CiachConfig(),
        colorDefault: true,
        progressDefault: true,
      );
      expect(auto.useColor, isTrue);
      expect(auto.showProgress, isTrue);

      final fromConfig = resolveOptions(
        parser.parse(const []),
        const CiachConfig(color: false, progress: false),
        colorDefault: true,
        progressDefault: true,
      );
      expect(fromConfig.useColor, isFalse);
      expect(fromConfig.showProgress, isFalse);

      final fromArgs = resolveOptions(
        parser.parse(const ['--no-color', '--no-progress']),
        const CiachConfig(color: true, progress: true),
        colorDefault: true,
        progressDefault: true,
      );
      expect(fromArgs.useColor, isFalse);
      expect(fromArgs.showProgress, isFalse);
    });

    test('verbose comes from the command line or the config', () {
      expect(resolve(const ['--verbose']).verbose, isTrue);
      expect(resolve(const ['-v']).verbose, isTrue);
      expect(resolve(const [], const CiachConfig(verbose: true)).verbose, true);
      expect(
        resolve(const [
          '--no-verbose',
        ], const CiachConfig(verbose: true)).verbose,
        isFalse,
      );
    });

    test('verbose supersedes the progress line', () {
      // Both would write to stderr, the progress line overwriting itself in
      // place — so verbose wins and progress is switched off, however it was
      // asked for.
      expect(
        resolveOptions(
          parser.parse(const ['--verbose', '--progress']),
          const CiachConfig(),
          colorDefault: false,
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      expect(
        resolveOptions(
          parser.parse(const []),
          const CiachConfig(verbose: true, progress: true),
          colorDefault: false,
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      // …but plain progress still works when verbose is off.
      expect(
        resolveOptions(
          parser.parse(const ['--progress']),
          const CiachConfig(verbose: true),
          colorDefault: false,
          progressDefault: false,
        ).showProgress,
        isFalse,
      );
      expect(resolve(const ['--progress']).showProgress, isTrue);
    });

    test('rejects a non-positive --concurrency', () {
      for (final value in ['0', '-1', 'lots']) {
        expect(
          () => resolve(['--concurrency', value]),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('--concurrency must be a positive integer'),
            ),
          ),
          reason: 'for --concurrency $value',
        );
      }
    });

    test('rejects an unknown --kinds value', () {
      expect(
        () => resolve(const ['-k', 'klass']),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains("Unknown kind 'klass'"),
          ),
        ),
      );
    });
  });
}

/// A [FormatException] whose message names [origin] and matches [message].
Matcher isFormatException(String origin, Matcher message) =>
    isA<FormatException>()
        .having((e) => e.message, 'message', startsWith('$origin:'))
        .having((e) => e.message, 'message', message);
