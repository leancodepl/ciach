import 'dart:io';

import 'package:ciach/src/path_dependents.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String repository;
  late String core;

  void write(String path, String contents) => File(p.join(repository, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUp(() {
    repository = p.normalize(
      Directory.systemTemp.createTempSync('ciach_path_dependents_').path,
    );
    core = p.join(repository, 'pkgs', 'core');
    Directory(p.join(repository, '.git')).createSync();
    write('pkgs/core/pubspec.yaml', 'name: core');
    write('pkgs/app/pubspec.yaml', '''
name: app
dependencies:
  core: {path: ../core}
''');
    write('pkgs/other/pubspec.yaml', '''
name: other
dependencies:
  unrelated: {path: ../unrelated}
''');
  });

  tearDown(() => Directory(repository).deleteSync(recursive: true));

  test('names the packages outside the analysis root', () {
    expect(pathDependentsOutside(core, core), [
      p.join(repository, 'pkgs', 'app'),
    ]);
  });

  test('names a dependent above the scanned package', () {
    write('pubspec.yaml', '''
name: root_app
dependencies:
  core: {path: pkgs/core}
''');
    final dependents = pathDependentsOutside(core, core);
    expect(dependents, [repository, p.join(repository, 'pkgs', 'app')]);
    // The analysis root to suggest is the repository, not its parent.
    expect(commonAncestor([core, ...dependents]), repository);
  });

  test('is empty for a package at the repository root', () {
    write('pubspec.yaml', 'name: root_app');
    expect(pathDependentsOutside(repository, repository), isEmpty);
  });

  test('is empty when the analysis root covers them', () {
    expect(pathDependentsOutside(core, p.join(repository, 'pkgs')), isEmpty);
  });

  test('is empty for a pub workspace member', () {
    write('pkgs/core/pubspec.yaml', 'name: core\nresolution: workspace\n');
    expect(pathDependentsOutside(core, core), isEmpty);
  });

  test('is empty outside a git repository', () {
    Directory(p.join(repository, '.git')).deleteSync();
    expect(pathDependentsOutside(core, core), isEmpty);
  });
}
