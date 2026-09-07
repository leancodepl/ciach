@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `dart compile exe` / `dart build cli` / `dart install` produce a binary in
/// which `Platform.resolvedExecutable` is ciach itself, not the SDK. Before
/// #42 was fixed, such a binary spawned itself as the analysis server and
/// failed every run with `The client closed with pending request "initialize"`.
void main() {
  final fixturePath = p.join(Directory.current.path, 'example');
  final sdkBin = p.dirname(Platform.resolvedExecutable);
  late Directory tmp;
  late String binary;

  setUpAll(() async {
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

    tmp = Directory.systemTemp.createTempSync('ciach_compiled_test');
    binary = p.join(tmp.path, Platform.isWindows ? 'ciach.exe' : 'ciach');
    final compile = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      p.join('bin', 'ciach.dart'),
      '-o',
      binary,
    ]);
    expect(compile.exitCode, 0, reason: '${compile.stdout}\n${compile.stderr}');
  });

  tearDownAll(() => tmp.deleteSync(recursive: true));

  Future<ProcessResult> run(Map<String, String> environment) => Process.run(
    binary,
    [fixturePath, '--no-progress', '--include', 'lib/orphans.dart'],
    environment: environment,
    includeParentEnvironment: false,
  );

  test('finds the SDK on PATH and analyzes', () async {
    final result = await run({'PATH': sdkBin});
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('UnusedClass'));
  });

  test(
    'with no SDK on PATH, fails fast with a hint instead of hanging',
    () async {
      final result = await run({'PATH': tmp.path});
      expect(result.exitCode, 2);
      expect(result.stderr, contains('Could not find the Dart SDK'));
      expect(result.stderr, contains('--dart'));
      expect(result.stderr, isNot(contains('pending request')));
    },
  );
}
