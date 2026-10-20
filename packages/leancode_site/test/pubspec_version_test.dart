/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:leancode_site/server.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('leancode_site_version_');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  test(
    'reads the version of the named package from the first pubspec that declares it',
    () {
      final other = File('${dir.path}/other.yaml')
        ..writeAsStringSync('name: other\nversion: 9.9.9\n');
      final own = File('${dir.path}/own.yaml')
        ..writeAsStringSync('name: sample\nversion: 1.2.3+4\n');
      expect(
        versionFromPubspec('sample', pubspecs: [other.path, own.path]),
        '1.2.3+4',
      );
    },
  );

  test('skips pubspecs that do not exist', () {
    final own = File('${dir.path}/own.yaml')
      ..writeAsStringSync('name: sample\nversion: 1.2.3\n');
    expect(
      versionFromPubspec(
        'sample',
        pubspecs: ['${dir.path}/missing.yaml', own.path],
      ),
      '1.2.3',
    );
  });

  test('throws when no pubspec declares the package', () {
    final other = File('${dir.path}/other.yaml')
      ..writeAsStringSync('name: other\nversion: 9.9.9\n');
    expect(
      () => versionFromPubspec('sample', pubspecs: [other.path]),
      throwsStateError,
    );
  });
}
