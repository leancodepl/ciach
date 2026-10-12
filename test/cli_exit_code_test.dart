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

import 'package:ciach/src/cli/ci.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Drives the real binary and asserts its exit code.
  final fixturePath = p.join(Directory.current.path, 'example');
  final entrypoint = p.join(Directory.current.path, 'bin', 'ciach.dart');

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

  /// Runs ciach on the fixture. Every runner's variable is blanked first, so
  /// the CI the test itself is on neither shows through nor outranks the one
  /// [environment] sets: a run is local unless a test says otherwise.
  Future<ProcessResult> runCli(
    List<String> args, {
    Map<String, String> environment = const {},
    String? workingDirectory,
  }) => Process.run(
    Platform.resolvedExecutable,
    ['run', entrypoint, fixturePath, '--no-progress', ...args],
    workingDirectory: workingDirectory,
    environment: {
      for (final runner in CiRunner.values) ...{
        runner.variable: '',
        ?runner.checkoutVariable: '',
      },
      ...environment,
    },
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

  group('CI', () {
    test('without it, findings are reported as text and exit 0', () async {
      final result = await runCli(publicOnly);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('UnusedClass'));
      expect(result.stdout, isNot(contains('::warning')));
    });

    test('--ci fails on findings, --no-set-exit-if-changed opts out', () async {
      final failing = await runCli([...publicOnly, '--ci']);
      expect(
        failing.exitCode,
        1,
        reason: '${failing.stdout}\n${failing.stderr}',
      );
      expect(failing.stdout, isNot(contains('::warning')));

      final reporting = await runCli([
        ...publicOnly,
        '--ci',
        '--no-set-exit-if-changed',
      ]);
      expect(
        reporting.exitCode,
        0,
        reason: '${reporting.stdout}\n${reporting.stderr}',
      );
    });

    const githubActions = {'GITHUB_ACTIONS': 'true'};

    test('GITHUB_ACTIONS turns on annotations and the exit code', () async {
      final result = await runCli(publicOnly, environment: githubActions);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, contains('::warning file='));
      expect(result.stdout, contains('UnusedClass'));
    });

    test('paths start at the checkout, wherever ciach runs from', () async {
      final result = await runCli(
        publicOnly,
        environment: {
          ...githubActions,
          'GITHUB_WORKSPACE': p.dirname(fixturePath),
        },
        workingDirectory: fixturePath,
      );
      expect(result.stdout, contains('file=example/lib/orphans.dart,'));
    });

    test('--no-ci keeps the local defaults on GitHub Actions', () async {
      final result = await runCli([
        ...publicOnly,
        '--no-ci',
      ], environment: githubActions);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stdout, isNot(contains('::warning')));
    });

    test('the log, on by default, says which service was detected', () async {
      const gitlab = {'GITLAB_CI': 'true'};
      final result = await runCli(publicOnly, environment: gitlab);
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      // Verbose goes to stderr, the report to stdout.
      expect(result.stderr, contains('On GitLab CI (GITLAB_CI is set)'));
      expect(result.stderr, contains('Settings for this run:'));
      expect(result.stdout, isNot(contains('Settings for this run:')));

      final quiet = await runCli([
        ...publicOnly,
        '--no-verbose',
      ], environment: gitlab);
      expect(quiet.stderr, isNot(contains('On GitLab CI')));
    });
  });

  test('--analysis-root that does not exist -> usage error', () async {
    final result = await runCli([
      '--analysis-root',
      p.join(fixturePath, 'no', 'such', 'dir'),
    ]);
    expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Analysis root does not exist'));
  });

  test('--analysis-root below the analyzed path -> usage error', () async {
    // Narrowing would drop references rather than add them.
    final result = await runCli([
      '--analysis-root',
      p.join(fixturePath, 'lib'),
    ]);
    expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('must contain the analyzed path'));
  });

  test('--analysis-root equal to the analyzed path is accepted', () async {
    final result = await runCli([
      ...publicOnly,
      '--analysis-root',
      fixturePath,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('UnusedClass'));
  });
}
