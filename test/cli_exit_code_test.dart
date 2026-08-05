/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Drives the real binary and asserts its exit code.
  final fixturePath = p.join(Directory.current.path, 'example');
  final entrypoint = p.join('bin', 'ciach.dart');

  setUpAll(() async {
    // pub get first: the analyzer needs the fixture's package_config.json.
    final config = File(
      p.join(fixturePath, '.dart_tool', 'package_config.json'),
    );
    if (!config.existsSync()) {
      final result = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: fixturePath);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  Future<ProcessResult> runCli(List<String> args) => Process.run(
    Platform.resolvedExecutable,
    ['run', entrypoint, fixturePath, '--no-progress', ...args],
  );

  // orphans.dart: unused public only; greeting.dart: also an unused private one.
  const publicOnly = ['--include', 'lib/orphans.dart'];
  const withPrivate = ['--include', 'lib/greeting.dart'];

  test(
    '--set-exit-if-changed --no-fail-public: only public unused -> exit 0',
    () async {
      final result = await runCli([
        ...publicOnly,
        '--set-exit-if-changed',
        '--no-fail-public',
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      // Public findings are still reported, just not counted toward the exit.
      expect(result.stdout, contains('UnusedClass'));
    },
  );

  test(
    '--set-exit-if-changed --no-fail-public: an unused private -> exit 1',
    () async {
      final result = await runCli([
        ...withPrivate,
        '--set-exit-if-changed',
        '--no-fail-public',
      ]);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('_danglingPrivate'));
    },
  );

  test('--set-exit-if-changed alone: public counts -> exit 1', () async {
    final result = await runCli([...publicOnly, '--set-exit-if-changed']);
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
  });
}
