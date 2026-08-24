/*
 * AI-Provenance:
 *   model: claude-opus-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

@Timeout(Duration(minutes: 2))
library;

import 'dart:io';

import 'package:ciach/src/version.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  final entrypoint = p.join('bin', 'ciach.dart');

  test('ciachVersion matches the pubspec version', () {
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as Map;
    expect(
      ciachVersion,
      pubspec['version'],
      reason:
          'A release bumped pubspec.yaml without lib/src/version.dart (or the '
          'other way around); --version would report the wrong number.',
    );
  });

  test('--version prints the version and exits 0', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      entrypoint,
      '--version',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, 'ciach $ciachVersion\n');
  });

  test('--help leads with the version', () async {
    final result = await Process.run(Platform.resolvedExecutable, [
      'run',
      entrypoint,
      '--help',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, startsWith('ciach $ciachVersion\n'));
  });
}
