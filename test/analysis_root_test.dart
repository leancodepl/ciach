@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/remover.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // A two-package monorepo wired by a `path:` dependency, the layout whose
  // cross-package references the analyzer misses (a pub workspace resolves
  // them itself).
  //
  // The `package_config.json` files are hand-written, and mirror what pub
  // generates: `core` sees only itself, `app` sees both. A `core` config that
  // also listed `app` would put both in one analysis context and hide the
  // false positive under test.
  late Directory repo;
  late String corePath;
  late String appFile;

  /// A `package_config.json` as pub would write it for [packages], the first
  /// of which is the package that owns the file.
  String packageConfig(List<String> packages) {
    final entries = [
      for (final name in packages)
        '    { "name": "$name", "rootUri": "${name == packages.first ? '../' : '../../$name'}", "packageUri": "lib/", "languageVersion": "3.10" }',
    ];
    return '{\n  "configVersion": 2,\n  "packages": [\n${entries.join(',\n')}\n  ]\n}\n';
  }

  void write(String path, String contents) => File(p.join(repo.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() {
    repo = Directory.systemTemp.createTempSync('ciach_analysis_root_');
    corePath = p.join(repo.path, 'pkgs', 'core');
    appFile = p.join(repo.path, 'pkgs', 'app', 'lib', 'app.dart');

    write('pkgs/core/pubspec.yaml', '''
name: core
version: 1.0.0
environment:
  sdk: ^3.10.0
''');
    write('pkgs/app/pubspec.yaml', '''
name: app
environment:
  sdk: ^3.10.0
dependencies:
  core:
    path: ../core
''');
    write('pkgs/core/lib/core.dart', '''
/// Called only from the sibling `app` package.
void usedByApp() {}

/// Called from nowhere at all.
void deadEverywhere() {}
''');
    write('pkgs/app/lib/app.dart', '''
import 'package:core/core.dart';

void main() => usedByApp();
''');
    // `core` has no dependencies, so pub would list only `core` here.
    write('pkgs/core/.dart_tool/package_config.json', packageConfig(['core']));
    write(
      'pkgs/app/.dart_tool/package_config.json',
      packageConfig(['app', 'core']),
    );
  });

  tearDown(() => repo.deleteSync(recursive: true));

  Future<FinderResult> run({String? analysisRoot}) =>
      Ciach(.new(rootPath: corePath, analysisRootPath: analysisRoot)).run();

  Set<String> namesOf(FinderResult result) => {
    for (final decl in result.unused) decl.name,
  };

  test('without an analysis root a sibling package is invisible', () async {
    final result = await run();

    // `app` calls it, nothing in `core` does, and `app` is outside the
    // analyzed root.
    expect(namesOf(result), {'usedByApp', 'deadEverywhere'});
  });

  test('an analysis root above the package counts its references', () async {
    final result = await run(analysisRoot: repo.path);

    expect(namesOf(result), {'deadEverywhere'});
  });

  test('widening does not scan the sibling package', () async {
    final result = await run(analysisRoot: repo.path);

    // Only `core` is scanned, so paths stay relative to it.
    expect(result.filesScanned, 1);
    expect(result.unused.map((d) => d.filePath), everyElement('lib/core.dart'));
  });

  test('the analysis root may be the package itself', () async {
    final result = await run(analysisRoot: corePath);

    expect(namesOf(result), {'usedByApp', 'deadEverywhere'});
  });

  test('--remove only touches the scanned package', () async {
    final before = File(appFile).readAsStringSync();
    final result = await run(analysisRoot: repo.path);

    removeDeclarations(result.unused, corePath);

    final core = File(p.join(corePath, 'lib', 'core.dart')).readAsStringSync();
    expect(core, contains('usedByApp'));
    expect(core, isNot(contains('deadEverywhere')));
    // The sibling package is analyzed, never edited.
    expect(File(appFile).readAsStringSync(), before);
  });
}
