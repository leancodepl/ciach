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

    // Only the hand-written source is a candidate; the `.g.dart` file and the
    // banner-marked file are excluded from the scan…
    expect(rel(result.candidates), {'lib/model.dart'});
    // …but both are still returned for warming so references from them
    // resolve.
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
    // The generated file is warmed even though it doesn't match the include
    // glob that scopes the scan.
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

  test('a file with a custom suffix is treated as generated only when '
      'additionalGeneratedSuffixes lists it', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/embed.gc.dart', 'class Embed {}');

    // Without the option, the custom-suffix file is an ordinary candidate: it
    // has neither a built-in suffix nor a generated-code banner.
    final withoutOption = discoverDartFilesSplit(
      FinderOptions(rootPath: tempDir.path),
    );
    expect(rel(withoutOption.candidates), {
      'lib/model.dart',
      'lib/embed.gc.dart',
    });
    expect(withoutOption.warmOnly, isEmpty);

    // With the suffix configured, the file is excluded from candidates but
    // still warmed so references from it resolve.
    final withOption = discoverDartFilesSplit(
      FinderOptions(
        rootPath: tempDir.path,
        additionalGeneratedSuffixes: const ['.gc.dart'],
      ),
    );
    expect(rel(withOption.candidates), {'lib/model.dart'});
    expect(rel(withOption.warmOnly), {'lib/embed.gc.dart'});
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
