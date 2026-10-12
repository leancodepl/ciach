import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:test/test.dart';

import '../support/config.dart';

void main() {
  group('ConfigFile.parse', () {
    test('reads every option', () {
      // Checked through the merge, which is what the CLI does with them.
      final resolved = resolveFile('''
path: packages/app
analysis-root: .
public: false
exported: false
generated: true
project-config: false
unused-translations: true
overrides: true
operators: true
unused-union-members: true
report-tojson: true
transitive: true
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
concurrency: 4
dart: /sdk/bin/dart
''');

      expect(resolved.rootPath, 'packages/app');
      expect(resolved.analysisRootPath, '.');
      expect(resolved.includePublic, isFalse);
      expect(resolved.includeExported, isFalse);
      expect(resolved.includeGenerated, isTrue);
      expect(resolved.projectConfig, isFalse);
      expect(resolved.unusedTranslations, isTrue);
      expect(resolved.overrides, isTrue);
      expect(resolved.operators, isTrue);
      expect(resolved.unusedUnionMembers, isTrue);
      expect(resolved.reportToJson, isTrue);
      expect(resolved.transitive, isTrue);
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
      expect(resolved.additionalGeneratedSuffixes, ['.gc.dart']);
      expect(resolved.additionalGeneratedGlobs, ['lib/l10n/**']);
      expect(resolved.kinds, <SymbolKind>{.class$, .function});
      expect(resolved.format, 'github');
      expect(resolved.color, isTrue);
      expect(resolved.showProgress, isTrue);
      expect(resolved.concurrency, 4);
      expect(resolved.dartExecutable, '/sdk/bin/dart');
      // On its own, since it forces `progress` off.
      expect(resolveFile('verbose: true').verbose, isTrue);
    });

    test('covers every command-line option', () {
      // Anything settable on the command line is settable in the file. The
      // other way round holds too, but for the `entry-points` list, which has
      // no command-line spelling.
      final cliOnly = {'help', 'version', 'config', 'no-config'};
      final optionNames = argParser.options.keys.toSet().difference(cliOnly);

      expect(configKeys.difference({'path', 'entry-points'}), optionNames);
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
          aFormatException('ciach.yaml', contains("unknown option 'publik'")),
        ),
      );
    });

    test('rejects a top-level document that is not a map', () {
      expect(
        () => ConfigFile.parse('- public', origin: 'ciach.yaml'),
        throwsA(
          aFormatException('ciach.yaml', contains('must be a map of options')),
        ),
      );
    });

    test('rejects malformed YAML', () {
      expect(
        () => ConfigFile.parse('public: [unclosed', origin: 'ciach.yaml'),
        throwsA(aFormatException('ciach.yaml', contains('not valid YAML'))),
      );
    });

    test('rejects a non-boolean flag', () {
      expect(
        () => resolveFile('public: sometimes'),
        throwsA(
          aFormatException(
            'ciach.yaml',
            contains("'public' must be true or false, got a string"),
          ),
        ),
      );
    });

    test('rejects a non-string in a list', () {
      expect(
        () => resolveFile('exclude: [1]'),
        throwsA(aFormatException('ciach.yaml', contains('a list of strings'))),
      );
    });

    test('rejects an unknown format', () {
      expect(
        () => resolveFile('format: xml'),
        throwsA(aFormatException('ciach.yaml', contains('text, json, github'))),
      );
    });

    test('rejects an unknown kind', () {
      expect(
        () => resolveFile('kinds: [klass]'),
        throwsA(
          aFormatException('ciach.yaml', contains("Unknown kind 'klass'")),
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
          throwsA(aFormatException('ciach.yaml', contains(message))),
          reason: 'for $source',
        );
      }
    });

    test('rejects a non-positive concurrency', () {
      for (final value in ['0', '-2', 'many', '1.5']) {
        expect(
          () => resolveFile('concurrency: $value'),
          throwsA(aFormatException('ciach.yaml', contains('positive integer'))),
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
        '--project-config',
        '--unused-translations',
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
        '--generated-glob',
        'lib/l10n/**',
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
          throwsA(aFormatException('ciach.yaml', contains("'$key'"))),
          reason: 'for a wrong value under $key',
        );
      }
    });
  });
}
