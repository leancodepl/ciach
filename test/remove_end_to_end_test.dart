@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The whole pipeline against a throwaway package: find, remove, and confirm
/// with `dart analyze` that what is left still compiles — no emptied
/// extension shell, no file of nothing but imports, no dangling import.
void main() {
  late Directory pkg;

  void write(String relativePath, String content) {
    File(p.join(pkg.path, p.joinAll(p.posix.split(relativePath))))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  String read(String relativePath) => File(
    p.join(pkg.path, p.joinAll(p.posix.split(relativePath))),
  ).readAsStringSync();

  setUpAll(() async {
    pkg = Directory.systemTemp.createTempSync('ciach_e2e_');
    write('pubspec.yaml', 'name: e2e\nenvironment:\n  sdk: ^3.10.0\n');
    write('lib/helpers.dart', '''
/// Every member is dead: the whole extension must go.
extension DeadExtras on int {
  int tripled() => this * 3;

  int quadrupled() => this * 4;
}

extension LiveExtras on int {
  int doubled() => this * 2;

  int halved() => this ~/ 2;
}
''');
    write('lib/only_dead.dart', '''
// A file with nothing live in it.

import 'dart:async';

/// Dead.
FutureOr<void> deadFn() {}
''');
    write('lib/main.dart', '''
import 'package:e2e/helpers.dart';
import 'package:e2e/only_dead.dart';

int use() => 4.doubled();
''');
    write('bin/app.dart', '''
import 'package:e2e/main.dart';

void main() => print(use());
''');
    const testConfig = '''
import 'dart:async';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await testMain();
}
''';
    write('test/flutter_test_config.dart', testConfig);
    // No dependencies, so offline resolution is enough for a package config.
    final pubGet = await Process.run(Platform.resolvedExecutable, [
      'pub',
      'get',
      '--offline',
    ], workingDirectory: pkg.path);
    expect(pubGet.exitCode, 0, reason: '${pubGet.stdout}\n${pubGet.stderr}');
  });

  tearDownAll(() => pkg.deleteSync(recursive: true));

  test('find, remove, and the package still analyzes cleanly', () async {
    final result = await Ciach(FinderOptions(rootPath: pkg.path)).run();
    final names = result.unused.map((d) => d.qualifiedName).toSet();
    expect(
      names,
      containsAll(['DeadExtras', 'tripled', 'quadrupled', 'halved', 'deadFn']),
    );
    expect(names, isNot(contains('LiveExtras')));
    expect(names, isNot(contains('testExecutable')));
    expect(names, isNot(contains('use')));

    final removal = removeDeclarations(result.unused, pkg.path);
    expect(removal.deletedFiles, ['lib/only_dead.dart']);
    expect(removal.removedDirectives, [
      (
        filePath: 'lib/main.dart',
        directive: "import 'package:e2e/only_dead.dart';",
      ),
    ]);

    final helpers = read('lib/helpers.dart');
    expect(helpers, isNot(contains('DeadExtras')));
    expect(helpers, isNot(contains('halved')));
    expect(helpers, contains('extension LiveExtras on int {'));
    expect(read('lib/main.dart'), isNot(contains('only_dead')));
    expect(read('test/flutter_test_config.dart'), contains('testExecutable'));

    final analyze = await Process.run(Platform.resolvedExecutable, [
      'analyze',
      '--fatal-infos',
    ], workingDirectory: pkg.path);
    expect(analyze.exitCode, 0, reason: '${analyze.stdout}\n${analyze.stderr}');
  });
}
