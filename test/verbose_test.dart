import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:test/test.dart';

void main() {
  final parser = buildParser();

  ResolvedOptions resolve(List<String> arguments, [CiachConfig? config]) =>
      resolveOptions(
        parser.parse(arguments),
        config ?? const CiachConfig(),
        colorDefault: false,
        progressDefault: false,
      );

  group('describeConfigSource', () {
    test('names the file it read and every option it set', () {
      const config = CiachConfig(public: false, exclude: ['test/**']);
      final lines = describeConfigSource(
        const LoadedConfig(config: config, path: '/pkg/ciach.yaml'),
        projectDir: '/pkg',
      );

      expect(lines, [
        'Read config from /pkg/ciach.yaml.',
        '  It sets 2 options:',
        '    public: false',
        '    exclude: test/**',
      ]);
    });

    test('says so when the file it read is empty', () {
      final lines = describeConfigSource(
        const LoadedConfig(config: CiachConfig(), path: '/pkg/ciach.yaml'),
        projectDir: '/pkg',
      );

      expect(lines, [
        'Read config from /pkg/ciach.yaml.',
        contains('It sets nothing'),
      ]);
    });

    test('names the directory it searched when nothing was found', () {
      final lines = describeConfigSource(
        const LoadedConfig(config: CiachConfig(), path: null),
        projectDir: 'packages/app',
      );

      expect(lines, [
        allOf(contains('No ciach.yaml in packages/app'), contains('defaults')),
      ]);
    });

    test('names the file it skipped for --no-config', () {
      final lines = describeConfigSource(
        const LoadedConfig(
          config: CiachConfig(),
          path: '/pkg/ciach.yaml',
          ignored: true,
        ),
        projectDir: '/pkg',
      );

      expect(lines, [
        'Ignoring the config file /pkg/ciach.yaml (--no-config).',
      ]);
    });

    test('says --no-config changed nothing when there was no file', () {
      final lines = describeConfigSource(
        const LoadedConfig(config: CiachConfig(), path: null, ignored: true),
        projectDir: '/pkg',
      );

      expect(lines, [
        allOf(contains('--no-config'), contains('no ciach.yaml in /pkg')),
      ]);
    });
  });

  group('describeSettings', () {
    List<String> describe([List<String> arguments = const []]) =>
        describeSettings(
          resolve(arguments),
          rootPath: '/pkg',
          dartExecutable: '/sdk/bin/dart',
        );

    test('lists every setting the run uses, under one key per option', () {
      final lines = describe();

      expect(lines.first, 'Settings for this run:');
      final keys = lines.skip(1).map((l) => l.trim().split(':').first).toSet();
      // `path` stands in for the positional argument, as in the config file.
      expect(keys, configKeys);
    });

    test('reports the resolved values, not the raw arguments', () {
      final lines = describe(const ['--no-public', '-e', 'test/**', '-j', '4']);

      expect(lines, containsAll(<String>['  path: /pkg', '  public: false']));
      expect(lines, contains('  exclude: test/**'));
      expect(lines, contains('  concurrency: 4'));
      expect(lines, contains('  dart: /sdk/bin/dart'));
    });

    test('marks an empty list rather than printing nothing', () {
      expect(describe(), contains('  exclude: (none)'));
      expect(describe(), contains('  include: (none)'));
      expect(describe(), contains('  generated-suffix: (none)'));
    });

    test('flags the full kind set as such, and lists a restricted one', () {
      expect(
        describe().singleWhere((l) => l.startsWith('  kinds:')),
        allOf(contains('class'), endsWith('(all)')),
      );
      expect(
        describe(const [
          '-k',
          'class,method',
        ]).singleWhere((l) => l.startsWith('  kinds:')),
        '  kinds: class, method',
      );
    });

    test('lists as many kinds as the finder defaults to', () {
      final kinds = describe()
          .singleWhere((l) => l.startsWith('  kinds:'))
          .replaceFirst('  kinds: ', '')
          .replaceFirst(' (all)', '')
          .split(', ');

      // Two aliases can map to one symbol kind, so labels can be fewer.
      expect(kinds, hasLength(FinderOptions.defaultKinds.length));
    });
  });
}
