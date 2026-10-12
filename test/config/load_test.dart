import 'dart:io';

import 'package:ciach/src/cli/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ConfigFile.load', () {
    late Directory tempDir;

    setUp(() {
      tempDir = .systemTemp.createTempSync('ciach_config_test_');
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
}
