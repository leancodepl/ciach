import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final parser = buildParser();

  /// Resolves [arguments] against [config], the terminal-probed defaults given
  /// explicitly so no test depends on the terminal it runs in.
  ResolvedOptions resolveWith(
    List<String> arguments,
    ConfigFile config, {
    required bool colorDefault,
    required bool progressDefault,
  }) => resolveOptions(
    resolveConfiguration(parser.parse(arguments), config),
    colorDefault: colorDefault,
    progressDefault: progressDefault,
  );

  /// As above, with both auto-detected settings off.
  ResolvedOptions resolve(List<String> arguments, [ConfigFile? config]) =>
      resolveWith(
        arguments,
        config ?? const .empty(),
        colorDefault: false,
        progressDefault: false,
      );

  /// What a config [source] alone resolves to.
  ResolvedOptions resolveFile(String source) =>
      resolve(const [], .parse(source, origin: 'ciach.yaml'));

  group('ConfigFile.parse', () {
    test('reads every option', () {
      // Checked through the merge, which is what the CLI does with them.
      final resolved = resolveFile('''
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
color: true
progress: true
concurrency: 4
dart: /sdk/bin/dart
''');

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
      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.includeGlobs, ['lib/**']);
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart']);
      expect(resolved.kinds, <SymbolKind>{.class$, .function});
      expect(resolved.format, 'github');
      expect(resolved.useColor, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.concurrency, 4);
      expect(resolved.dartExecutable, '/sdk/bin/dart');
      // On its own, since it forces `progress` off.
      expect(resolveFile('verbose: true').verbose, isTrue);
    });

    test('covers every command-line option', () {
      // Anything settable on the command line is settable in the file.
      final cliOnly = {'help', 'version', 'config', 'no-config'};
      final optionNames = parser.options.keys.toSet().difference(cliOnly);

      expect(configKeys.difference({'path'}), optionNames);
    });

    test('settings lists what the file sets, and only that', () {
      final config = ConfigFile.parse('''
public: false
exclude: ['test/**']
concurrency: 4
''', origin: 'ciach.yaml');

      expect(config.settings, {
        'public': false,
        'exclude': ['test/**'],
        'concurrency': 4,
      });
      expect(config.path, 'ciach.yaml');
      expect(config.ignored, isFalse);
    });

    test('treats an empty or comment-only file as no settings', () {
      for (final source in ['', '\n', '# nothing here\n']) {
        expect(
          ConfigFile.parse(source, origin: 'ciach.yaml').settings,
          isEmpty,
          reason: 'for ${source.trim()}',
        );
      }
    });

    test('treats a valueless key as unset', () {
      final config = ConfigFile.parse('public:\n', origin: 'ciach.yaml');

      expect(config.settings, isEmpty);
      expect(resolve(const [], config).includePublic, isTrue);
    });

    test('accepts a bare string where a list is expected', () {
      expect(resolveFile("exclude: 'test/**'").excludeGlobs, ['test/**']);
    });

    test('accepts comma-separated kinds in one string', () {
      expect(resolveFile('kinds: class,method').kinds, <SymbolKind>{
        .class$,
        .method,
      });
    });

    test('rejects an unknown option, naming the file and valid keys', () {
      expect(
        () => ConfigFile.parse('publik: false', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains("unknown option 'publik'")),
        ),
      );
    });

    test('rejects a top-level document that is not a map', () {
      expect(
        () => ConfigFile.parse('- public', origin: 'ciach.yaml'),
        throwsA(
          isFormatException('ciach.yaml', contains('must be a map of options')),
        ),
      );
    });

    test('rejects malformed YAML', () {
      expect(
        () => ConfigFile.parse('public: [unclosed', origin: 'ciach.yaml'),
        throwsA(isFormatException('ciach.yaml', contains('not valid YAML'))),
      );
    });

    test('rejects a non-boolean flag', () {
      expect(
        () => resolveFile('public: sometimes'),
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
        () => resolveFile('exclude: [1]'),
        throwsA(isFormatException('ciach.yaml', contains('a list of strings'))),
      );
    });

    test('rejects an unknown format', () {
      expect(
        () => resolveFile('format: xml'),
        throwsA(
          isFormatException('ciach.yaml', contains('text, json, github')),
        ),
      );
    });

    test('rejects an unknown kind', () {
      expect(
        () => resolveFile('kinds: [klass]'),
        throwsA(
          isFormatException('ciach.yaml', contains("Unknown kind 'klass'")),
        ),
      );
    });

    test('rejects a non-positive concurrency', () {
      for (final value in ['0', '-2', 'many', '1.5']) {
        expect(
          () => resolveFile('concurrency: $value'),
          throwsA(
            isFormatException('ciach.yaml', contains('positive integer')),
          ),
          reason: 'for concurrency: $value',
        );
      }
    });

    test('checks the type of every key, even one the argv overrides', () {
      // Every option is given on the command line below, so only the eager
      // check when the file is parsed can still catch the bad value. A map fits
      // no setting, so it is the one wrong value that works for every key.
      const everyOption = [
        '--public',
        '--generated',
        '--overrides',
        '--operators',
        '--unused-union-members',
        '--report-tojson',
        '--set-exit-if-changed',
        '--remove',
        '--force',
        '-e',
        'test/**',
        '-i',
        'lib/**',
        '--generated-suffix',
        '.gc.dart',
        '-k',
        'class',
        '-f',
        'json',
        '--color',
        '--progress',
        '--verbose',
        '-j',
        '2',
        '--dart',
        '/sdk/bin/dart',
        'lib',
      ];

      for (final key in configKeys) {
        expect(
          () => resolve(
            everyOption,
            .parse('$key: {a: b}', origin: 'ciach.yaml'),
          ),
          throwsA(isFormatException('ciach.yaml', contains("'$key'"))),
          reason: 'for a map under $key',
        );
      }
    });
  });

  group('ConfigFile.load', () {
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

      final config = ConfigFile.load(projectDir: tempDir.path);

      expect(config.path, p.join(tempDir.path, 'ciach.yaml'));
      expect(config.settings['public'], isFalse);
    });

    test('discovers ciach.yaml only, not other spellings', () {
      write('ciach.yml', 'format: json');
      write('.ciach.yaml', 'format: json');

      expect(ConfigFile.load(projectDir: tempDir.path).path, isNull);

      write('ciach.yaml', 'format: github');

      expect(
        ConfigFile.load(projectDir: tempDir.path).settings['format'],
        'github',
      );
    });

    test('returns an empty config when the directory has none', () {
      final config = ConfigFile.load(projectDir: tempDir.path);

      expect(config.path, isNull);
      expect(config.settings, isEmpty);
    });

    test('does not look outside the project directory', () {
      write('ciach.yaml', 'public: false');
      final nested = Directory(p.join(tempDir.path, 'nested'))..createSync();

      expect(ConfigFile.load(projectDir: nested.path).path, isNull);
    });

    test('loads an explicit path from outside the project directory', () {
      write('elsewhere.yaml', 'format: json');
      final nested = Directory(p.join(tempDir.path, 'nested'))..createSync();

      final config = ConfigFile.load(
        projectDir: nested.path,
        explicitPath: p.join(tempDir.path, 'elsewhere.yaml'),
      );

      expect(config.settings['format'], 'json');
    });

    test('an explicit path wins over a discoverable file', () {
      write('ciach.yaml', 'format: github');
      write('other.yaml', 'format: json');

      final config = ConfigFile.load(
        projectDir: tempDir.path,
        explicitPath: p.join(tempDir.path, 'other.yaml'),
      );

      expect(config.settings['format'], 'json');
    });

    test('reports a missing explicit path', () {
      expect(
        () => ConfigFile.load(
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
      // Invalid on purpose: --no-config never parses it, so it can't fail.
      write('ciach.yaml', 'publik: [unclosed');

      final config = ConfigFile.load(projectDir: tempDir.path, ignore: true);

      expect(config.ignored, isTrue);
      expect(config.path, p.join(tempDir.path, 'ciach.yaml'));
      expect(config.settings, isEmpty);
    });

    test('ignore reports no path when there was no config anyway', () {
      final config = ConfigFile.load(projectDir: tempDir.path, ignore: true);

      expect(config.ignored, isTrue);
      expect(config.path, isNull);
    });

    test('ignore skips an explicit path, and its would-be errors', () {
      final config = ConfigFile.load(
        projectDir: tempDir.path,
        explicitPath: p.join(tempDir.path, 'nope.yaml'),
        ignore: true,
      );

      expect(config.path, isNull);
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
      expect(resolved.useColor, isTrue);
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
      ]);

      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart', '.pb.dart']);
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
      final auto = resolveWith(
        const [],
        const .empty(),
        colorDefault: true,
        progressDefault: true,
      );
      expect(auto.useColor, isTrue);
      expect(auto.showProgress, isTrue);

      final fromConfig = resolveWith(
        const [],
        .parse('color: false\nprogress: false', origin: 'c.yaml'),
        colorDefault: true,
        progressDefault: true,
      );
      expect(fromConfig.useColor, isFalse);
      expect(fromConfig.showProgress, isFalse);

      final fromArgs = resolveWith(
        const ['--no-color', '--no-progress'],
        .parse('color: true\nprogress: true', origin: 'c.yaml'),
        colorDefault: true,
        progressDefault: true,
      );
      expect(fromArgs.useColor, isFalse);
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
          colorDefault: false,
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      expect(
        resolveWith(
          const [],
          .parse('verbose: true\nprogress: true', origin: 'c.yaml'),
          colorDefault: false,
          progressDefault: true,
        ).showProgress,
        isFalse,
      );
      expect(
        resolveWith(
          const ['--progress'],
          .parse('verbose: true', origin: 'c.yaml'),
          colorDefault: false,
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
          throwsA(isUsageException(contains('below the minimum (1)'))),
          reason: 'for --concurrency $value',
        );
      }
      expect(
        () => resolve(const ['--concurrency', 'lots']),
        throwsA(isUsageException(contains('lots'))),
      );
    });

    test('rejects an unknown --kinds value', () {
      expect(
        () => resolve(const ['-k', 'klass']),
        throwsA(isUsageException(contains("Unknown kind 'klass'"))),
      );
    });

    test('reports every problem at once, not just the first', () {
      // An out-of-range `--format` is not among them: an option's `allowed`
      // list is the arg parser's business, so that fails before resolution.
      expect(
        () => resolve(const ['-k', 'klass', '-j', '0']),
        throwsA(
          isUsageException(
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
        '--overrides',
        '-e',
        'test/**',
        '-j',
        '4',
      ]);
      final options = resolved.finderOptions();

      expect(options.rootPath, p.normalize(p.absolute('.')));
      expect(options.includePublic, isFalse);
      // Inverted for the finder.
      expect(options.skipOverrides, isFalse);
      expect(options.skipOperators, isTrue);
      expect(options.excludeGlobs, ['test/**']);
      expect(options.concurrency, 4);
      expect(options.onProgress, isNull);
    });
  });
}

/// A [UsageException] whose message matches [message].
Matcher isUsageException(Matcher message) =>
    isA<UsageException>().having((e) => e.message, 'message', message);

/// A [FormatException] whose message names [origin] and matches [message].
Matcher isFormatException(String origin, Matcher message) =>
    isA<FormatException>()
        .having((e) => e.message, 'message', startsWith('$origin:'))
        .having((e) => e.message, 'message', message);
