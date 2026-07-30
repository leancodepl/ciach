import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final parser = buildParser();

  group('describeConfigSource', () {
    test('names the file it read and every option it set', () {
      final lines = describeConfigSource(
        ConfigFile.parse(
          "public: false\nexclude: ['test/**']",
          origin: '/c.yaml',
        ),
        projectDir: '/pkg',
      );

      expect(lines, [
        'Read config from /c.yaml.',
        '  It sets 2 options:',
        '    public: false',
        '    exclude: test/**',
      ]);
    });

    test('says so when the file it read is empty', () {
      final lines = describeConfigSource(
        ConfigFile.parse('# nothing\n', origin: '/pkg/ciach.yaml'),
        projectDir: '/pkg',
      );

      expect(lines, [
        'Read config from /pkg/ciach.yaml.',
        contains('It sets nothing'),
      ]);
    });

    test('names the directory it searched when nothing was found', () {
      final lines = describeConfigSource(
        const ConfigFile.empty(),
        projectDir: 'packages/app',
      );

      expect(lines, [
        allOf(contains('No ciach.yaml in packages/app'), contains('defaults')),
      ]);
    });

    test('names the file it skipped for --no-config', () {
      final dir = Directory.systemTemp.createTempSync('ciach_verbose_test_');
      addTearDown(() => dir.deleteSync(recursive: true));
      File(p.join(dir.path, configFileName)).writeAsStringSync('public: false');

      final lines = describeConfigSource(
        ConfigFile.load(projectDir: dir.path, ignore: true),
        projectDir: dir.path,
      );

      expect(lines, [
        'Ignoring the config file ${p.join(dir.path, 'ciach.yaml')} (--no-config).',
      ]);
    });

    test('says --no-config changed nothing when there was no file', () {
      final dir = Directory.systemTemp.createTempSync('ciach_verbose_test_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final lines = describeConfigSource(
        ConfigFile.load(projectDir: dir.path, ignore: true),
        projectDir: dir.path,
      );

      expect(lines, [
        allOf(
          contains('--no-config'),
          contains('no ciach.yaml in ${dir.path}'),
        ),
      ]);
    });
  });

  group('describeSettings', () {
    List<String> describe([List<String> arguments = const []]) {
      final configuration = resolveConfiguration(
        parser.parse(arguments),
        const ConfigFile.empty(),
      );
      return describeSettings(
        configuration,
        resolveOptions(
          configuration,
          colorDefault: false,
          progressDefault: false,
        ),
        dartExecutable: '/sdk/bin/dart',
      );
    }

    test('lists every setting the run uses, under one key per option', () {
      final lines = describe();

      expect(lines.first, 'Settings for this run:');
      final keys = lines.skip(1).map((l) => l.trim().split(':').first).toSet();
      // `path` stands in for the positional argument, as in the config file.
      expect(keys, configKeys);
    });

    test('reports the resolved values, not the raw arguments', () {
      final lines = describe(const [
        '--no-public',
        '-e',
        'test/**',
        '-j',
        '4',
        '/pkg',
      ]);

      expect(lines, containsAll(<String>['  path: /pkg (command line)']));
      expect(lines, contains('  public: false (command line)'));
      expect(lines, contains('  exclude: test/** (command line)'));
      expect(lines, contains('  concurrency: 4 (command line)'));
      expect(lines, contains('  dart: /sdk/bin/dart (auto-detected)'));
    });

    test('names the layer each value came from', () {
      final configuration = resolveConfiguration(
        parser.parse(const ['--no-public']),
        ConfigFile.parse('format: json\nremove: true', origin: 'c.yaml'),
      );
      final lines = describeSettings(
        configuration,
        resolveOptions(
          configuration,
          colorDefault: false,
          progressDefault: false,
        ),
        dartExecutable: '/sdk/bin/dart',
      );

      expect(lines, contains('  public: false (command line)'));
      expect(lines, contains('  format: json (config file)'));
      expect(lines, contains('  remove: true (config file)'));
      expect(lines, contains('  concurrency: 16 (default)'));
      expect(lines, contains('  color: false (auto-detected)'));
    });

    test('marks an empty list rather than printing nothing', () {
      expect(describe(), contains('  exclude: (none) (default)'));
      expect(describe(), contains('  include: (none) (default)'));
      expect(describe(), contains('  generated-suffix: (none) (default)'));
    });

    test('lists the kinds, all of them by default', () {
      final kinds = describe()
          .singleWhere((l) => l.startsWith('  kinds:'))
          .replaceFirst('  kinds: ', '')
          .replaceFirst(' (default)', '')
          .split(', ');

      // Two aliases can map to one symbol kind, so labels can be fewer.
      expect(kinds, hasLength(FinderOptions.defaultKinds.length));
      expect(
        describe(const [
          '-k',
          'class,method',
        ]).singleWhere((l) => l.startsWith('  kinds:')),
        '  kinds: class, method (command line)',
      );
    });
  });
}
