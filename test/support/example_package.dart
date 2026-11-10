import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The absolute path of `example/`, a real package with a known mix of used
/// and unused declarations that doubles as the test fixture.
final examplePath = p.join(Directory.current.path, 'example');

/// Runs `dart pub get` in `example/` unless it has a package config: the
/// analysis server needs it to resolve the `package:` imports there.
Future<void> resolveExample() async {
  if (File(
    p.join(examplePath, '.dart_tool', 'package_config.json'),
  ).existsSync()) {
    return;
  }
  final result = await Process.run(Platform.resolvedExecutable, [
    'pub',
    'get',
  ], workingDirectory: examplePath);
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}
