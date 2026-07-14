import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ciach_discovery_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File(p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// Relative POSIX paths of [absolutePaths], for order-independent asserts.
  Set<String> rel(List<String> absolutePaths) => {
    for (final path in absolutePaths)
      p.split(p.relative(path, from: tempDir.path)).join('/'),
  };

  test('excludes generated files from candidates but keeps them for '
      'warming', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/model.g.dart', '// generated\nclass ModelGen {}');
    write(
      'lib/mapper.dart',
      '// GENERATED CODE - DO NOT MODIFY BY HAND\nclass Mapper {}',
    );

    final result = discoverDartFilesSplit(
      FinderOptions(rootPath: tempDir.path),
    );

    // The `.g.dart` and banner-marked files are excluded from candidates…
    expect(rel(result.candidates), {'lib/model.dart'});
    // …but still returned for warming.
    expect(rel(result.warmOnly), {'lib/model.g.dart', 'lib/mapper.dart'});
  });

  test('warm set ignores include/exclude globs (references can live '
      'anywhere)', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/other.dart', 'class Other {}');
    write('lib/model.g.dart', '// generated\nclass ModelGen {}');

    final result = discoverDartFilesSplit(
      FinderOptions(
        rootPath: tempDir.path,
        includeGlobs: const ['lib/model.dart'],
      ),
    );

    expect(rel(result.candidates), {'lib/model.dart'});
    // Warmed even though it doesn't match the include glob.
    expect(rel(result.warmOnly), {'lib/model.g.dart'});
  });

  test('with includeGenerated, generated files are candidates and the warm '
      'set is empty', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/model.g.dart', '// generated\nclass ModelGen {}');

    final result = discoverDartFilesSplit(
      FinderOptions(rootPath: tempDir.path, includeGenerated: true),
    );

    expect(rel(result.candidates), {'lib/model.dart', 'lib/model.g.dart'});
    expect(result.warmOnly, isEmpty);
  });

  test('generated files inside skipped dirs are excluded from both sets', () {
    write('lib/model.dart', 'class Model {}');
    write('build/gen.g.dart', '// generated\nclass Gen {}');
    write('.dart_tool/tool.g.dart', '// generated\nclass Tool {}');

    final result = discoverDartFilesSplit(
      FinderOptions(rootPath: tempDir.path),
    );

    expect(rel(result.candidates), {'lib/model.dart'});
    expect(result.warmOnly, isEmpty);
  });
}
