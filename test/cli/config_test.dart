import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:config/config.dart';
import 'package:test/test.dart';

import '../support/cli_options.dart';

void main() {
  group('ConfigFile.parse', () {
    test('reads every option', () {
      // Checked through the merge, which is what the CLI does with them.
      final resolved = resolveFile('''
path: packages/app
analysis-root: .
public: false
exported-packages: [packages/shared]
generated: true
project-config: false
unused-translations: false
also: [overrides, union-members, tojson]
transitive: false
set-exit-if-changed: true
remove: true
force: true
exclude:
  - 'test/**'
  - 'tool/**'
include:
  - 'lib/**'
generated-glob:
  - 'lib/l10n/**'
entry-points:
  - name: registerWith
    glob: 'lib/**_plugin.dart'
  - name: bootstrap
  - name: Harness.start
    glob: [test/a.dart, test/b.dart]
kinds: [class, function]
format: github
color: true
progress: true
dart: /sdk/bin/dart
''');

      expect(resolved.rootPath, 'packages/app');
      expect(resolved.analysisRootPath, '.');
      expect(resolved.includePublic, isFalse);
      expect(resolved.exportedPackages, ['packages/shared']);
      expect(resolved.includeGenerated, isTrue);
      expect(resolved.projectConfig, isFalse);
      expect(resolved.unusedTranslations, isFalse);
      expect(resolved.overrides, isTrue);
      expect(resolved.unusedUnionMembers, isTrue);
      expect(resolved.reportToJson, isTrue);
      expect(resolved.transitive, isFalse);
      expect(resolved.setExitIfChanged, isTrue);
      expect(resolved.remove, isTrue);
      expect(resolved.force, isTrue);
      expect(resolved.excludeGlobs, ['test/**', 'tool/**']);
      expect(resolved.includeGlobs, ['lib/**']);
      expect(resolved.entryPoints.map((e) => '$e'), [
        'registerWith in lib/**_plugin.dart',
        'bootstrap',
        'Harness.start in test/a.dart or test/b.dart',
      ]);
      expect(resolved.additionalGeneratedGlobs, ['lib/l10n/**']);
      expect(resolved.kinds, <SymbolKind>{.class$, .function});
      expect(resolved.format, 'github');
      expect(resolved.color, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.dartExecutable, '/sdk/bin/dart');
      // On its own, since it forces `progress` off.
      expect(resolveFile('verbose: true').verbose, isTrue);
    });

    test('covers every command-line option', () {
      // Anything settable on the command line is settable in the file. The
      // other way round holds too, but for the `entry-points` list, which has
      // no command-line spelling.
      final cliOnly = {'help', 'version', 'config', 'no-config'};
      final optionNames = buildParser().options.keys.toSet().difference(
        cliOnly,
      );

      expect(configKeys.difference({'path', 'entry-points'}), optionNames);
    });

    test('settings lists what the file sets, and only that', () {
      final config = ConfigFile.parse('''
public: false
exclude: ['test/**']
format: json
''', origin: 'ciach.yaml');

      expect(config.settings, {
        'public': false,
        'exclude': ['test/**'],
        'format': 'json',
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
          isFormatExceptionFrom(
            'ciach.yaml',
            contains("unknown option 'publik'"),
          ),
        ),
      );
    });

    test('names what replaced a removed option', () {
      Matcher removed(String message) => throwsA(
        isA<FormatException>().having((e) => e.message, 'message', message),
      );

      expect(
        () => ConfigFile.parse('overrides: true', origin: 'ciach.yaml'),
        removed(
          'ciach.yaml: `overrides` was removed: use `also: [overrides]`.',
        ),
      );
      expect(
        () => ConfigFile.parse('exported: false', origin: 'ciach.yaml'),
        removed(
          "ciach.yaml: `exported` was removed: use `exported-packages: ['**']`.",
        ),
      );
      expect(
        () => ConfigFile.parse(
          'generated-suffix: [.gc.dart]',
          origin: 'ciach.yaml',
        ),
        removed(
          "ciach.yaml: `generated-suffix` was removed: use `generated-glob: ['**/*.gc.dart']`.",
        ),
      );
      expect(
        () => ConfigFile.parse('fail-public: false', origin: 'ciach.yaml'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('ciach.yaml: `fail-public` was removed: '),
          ),
        ),
      );
    });

    test('says to drop a removed option set to what is the default now', () {
      expect(
        () => ConfigFile.parse('exported: true', origin: 'ciach.yaml'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'ciach.yaml: `exported` was removed: that is the default now, so drop it.',
          ),
        ),
      );
    });

    test(
      'says that operator overloads are reported now, for the removed `operators` option',
      () {
        expect(
          () => ConfigFile.parse('operators: true', origin: 'ciach.yaml'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'ciach.yaml: `operators` was removed: operator overloads are reported by default now, so drop it.',
            ),
          ),
        );
      },
    );

    test(
      'says that ciach no longer sends requests to an analysis server, for the removed `concurrency` option',
      () {
        expect(
          () => ConfigFile.parse('concurrency: 4', origin: 'ciach.yaml'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              'ciach.yaml: `concurrency` was removed: ciach no longer sends requests to an analysis server, so drop it.',
            ),
          ),
        );
      },
    );

    test(
      'says that operator overloads are reported now, for `operators` under also',
      () {
        expect(
          () => resolve(
            const [],
            .parse('also: [overrides, operators]', origin: 'ciach.yaml'),
          ),
          throwsA(
            isA<UsageException>().having(
              (e) => e.message,
              'message',
              contains(
                '`operators` was removed: operator overloads are reported by default now, so drop it.',
              ),
            ),
          ),
        );
      },
    );

    test('rejects an unknown value under also', () {
      expect(
        () =>
            resolve(const [], .parse('also: [override]', origin: 'ciach.yaml')),
        throwsA(
          isA<UsageException>().having(
            (e) => e.message,
            'message',
            contains("Unknown value 'override' for `also`."),
          ),
        ),
      );
    });

    test('--exported-packages lists the packages whose API is left out', () {
      expect(resolve(['--exported-packages', 'packages/*']).exportedPackages, [
        'packages/*',
      ]);
    });

    test('rejects a top-level document that is not a map', () {
      expect(
        () => ConfigFile.parse('- public', origin: 'ciach.yaml'),
        throwsA(
          isFormatExceptionFrom(
            'ciach.yaml',
            contains('must be a map of options'),
          ),
        ),
      );
    });

    test('rejects malformed YAML', () {
      expect(
        () => ConfigFile.parse('public: [unclosed', origin: 'ciach.yaml'),
        throwsA(
          isFormatExceptionFrom('ciach.yaml', contains('not valid YAML')),
        ),
      );
    });

    test('rejects a non-boolean flag', () {
      expect(
        () => resolveFile('public: sometimes'),
        throwsA(
          isFormatExceptionFrom(
            'ciach.yaml',
            contains("'public' must be true or false, got a string"),
          ),
        ),
      );
    });

    test('rejects a non-string in a list', () {
      expect(
        () => resolveFile('exclude: [1]'),
        throwsA(
          isFormatExceptionFrom('ciach.yaml', contains('a list of strings')),
        ),
      );
    });

    test(
      'rejects a non-string in the glob list of an entry point, naming the type of the item',
      () {
        expect(
          () => resolveFile('entry-points: [{name: a, glob: [lib/a.dart, 1]}]'),
          throwsA(
            isFormatExceptionFrom(
              'ciach.yaml',
              contains(
                "'entry-points[0].glob' must be a glob or a list of globs, got a number.",
              ),
            ),
          ),
        );
      },
    );

    test('rejects an unknown format', () {
      expect(
        () => resolveFile('format: xml'),
        throwsA(
          isFormatExceptionFrom(
            'ciach.yaml',
            contains(
              'text, json, github, azure, teamcity, sarif, checkstyle, gitlab',
            ),
          ),
        ),
      );
    });

    test('rejects an unknown kind', () {
      expect(
        () => resolveFile('kinds: [klass]'),
        throwsA(
          isFormatExceptionFrom('ciach.yaml', contains("Unknown kind 'klass'")),
        ),
      );
    });

    test('rejects the removed kind `constant` with what to use instead', () {
      expect(
        () => resolveFile('kinds: [constant]'),
        throwsA(
          isFormatExceptionFrom(
            'ciach.yaml',
            contains(
              '`constant` was removed: ciach reports a `const` variable as a `variable` or a `field`, so use those.',
            ),
          ),
        ),
      );
    });

    test('rejects a malformed entry point, naming the key', () {
      final cases = {
        'entry-points: {name: a}': 'a list of `{name, glob}` rules',
        'entry-points: [a]': "'entry-points[0]' must be `{name:",
        'entry-points: [{glob: lib/**}]': "'entry-points[0]' must be `{name:",
        'entry-points: [{name: 1}]': "'entry-points[0]' must be `{name:",
        'entry-points: [{name: a-b}]': 'not a declaration name',
        'entry-points: [{name: "Box<T>.convert"}]': 'type parameters are not',
        'entry-points: [{name: a, glob: 1}]': "'entry-points[0].glob' must be",
        'entry-points: [{name: a, glob: [1]}]':
            "'entry-points[0].glob' must be",
        "entry-points: [{name: a, glob: 'lib/['}]": "glob 'lib/[': expected",
        // An unknown field shows the whole rule back.
        'entry-points: [{name: a}, {name: b, file: x}]':
            "'entry-points[1]' must be `{name:",
      };
      for (final MapEntry(key: source, value: message) in cases.entries) {
        expect(
          () => resolveFile(source),
          throwsA(isFormatExceptionFrom('ciach.yaml', contains(message))),
          reason: 'for $source',
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
        '--project-config',
        '--unused-translations',
        '--also',
        'overrides',
        '--set-exit-if-changed',
        '--remove',
        '--force',
        '-e',
        'test/**',
        '-i',
        'lib/**',
        '--generated-glob',
        'lib/l10n/**',
        '-k',
        'class',
        '-f',
        'json',
        '--color',
        '--progress',
        '--verbose',
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
          throwsA(isFormatExceptionFrom('ciach.yaml', contains("'$key'"))),
          reason: 'for a wrong value under $key',
        );
      }
    });
  });
}
