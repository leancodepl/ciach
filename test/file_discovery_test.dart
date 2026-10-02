import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_discovery_test_');
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

    final result = discoverDartFilesSplit(.new(rootPath: tempDir.path));

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
      .new(rootPath: tempDir.path, includeGlobs: const ['lib/model.dart']),
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
      .new(rootPath: tempDir.path, includeGenerated: true),
    );

    expect(rel(result.candidates), {'lib/model.dart', 'lib/model.g.dart'});
    expect(result.warmOnly, isEmpty);
  });

  test('a file with a custom suffix is treated as generated only when '
      'additionalGeneratedSuffixes lists it', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/embed.gc.dart', 'class Embed {}');

    // Without the option, the custom-suffix file is an ordinary candidate.
    final withoutOption = discoverDartFilesSplit(.new(rootPath: tempDir.path));
    expect(rel(withoutOption.candidates), {
      'lib/model.dart',
      'lib/embed.gc.dart',
    });
    expect(withoutOption.warmOnly, isEmpty);

    // With the suffix configured, it's excluded from candidates but warmed.
    final withOption = discoverDartFilesSplit(
      .new(
        rootPath: tempDir.path,
        additionalGeneratedSuffixes: const ['.gc.dart'],
      ),
    );
    expect(rel(withOption.candidates), {'lib/model.dart'});
    expect(rel(withOption.warmOnly), {'lib/embed.gc.dart'});
  });

  test('a file matching additionalGeneratedGlobs is warmed, not scanned, and '
      'unlike an excluded one still opened', () {
    write('lib/model.dart', 'class Model {}');
    write('lib/l10n/l10n.dart', 'abstract class AppLocalizations {}');
    write('lib/l10n/l10n_pl.dart', 'class AppLocalizationsPl {}');
    // Its name ends like a gen-l10n file's, but it is hand-written.
    write('lib/src/status_l10n.dart', 'String status() => "";');

    final result = discoverDartFilesSplit(
      .new(
        rootPath: tempDir.path,
        additionalGeneratedGlobs: const ['lib/l10n/**'],
      ),
    );
    expect(rel(result.candidates), {
      'lib/model.dart',
      'lib/src/status_l10n.dart',
    });
    expect(rel(result.warmOnly), {
      'lib/l10n/l10n.dart',
      'lib/l10n/l10n_pl.dart',
    });

    final excluded = discoverDartFilesSplit(
      .new(rootPath: tempDir.path, excludeGlobs: const ['lib/l10n/**']),
    );
    expect(rel(excluded.candidates), {
      'lib/model.dart',
      'lib/src/status_l10n.dart',
    });
    expect(excluded.warmOnly, isEmpty);

    // --generated scans them like any other file.
    final scanned = discoverDartFilesSplit(
      .new(
        rootPath: tempDir.path,
        includeGenerated: true,
        additionalGeneratedGlobs: const ['lib/l10n/**'],
      ),
    );
    expect(scanned.candidates, hasLength(4));
    expect(scanned.warmOnly, isEmpty);
  });

  test('generated files inside skipped dirs are excluded from both sets', () {
    write('lib/model.dart', 'class Model {}');
    write('build/gen.g.dart', '// generated\nclass Gen {}');
    write('.dart_tool/tool.g.dart', '// generated\nclass Tool {}');

    final result = discoverDartFilesSplit(.new(rootPath: tempDir.path));

    expect(rel(result.candidates), {'lib/model.dart'});
    expect(result.warmOnly, isEmpty);
  });

  group('isGeneratedBanner', () {
    test('recognizes how each generator words it', () {
      for (final banner in [
        '// GENERATED CODE - DO NOT MODIFY BY HAND\n',
        '// dart format width=80\n// coverage:ignore-file\n// GENERATED CODE - DO NOT MODIFY BY HAND\n',
        '//\n//  Generated code. Do not modify.\n//  source: a.proto\n',
        '// This is a generated file - do not edit.\n',
        '/* AUTOMATICALLY GENERATED CODE DO NOT MODIFY */\n/*   To generate run: "serverpod generate"    */\n',
        '// Autogenerated from Pigeon (v22.4.0), do not edit directly.\n',
        '// AUTO GENERATED FILE, DO NOT EDIT.\n',
        '// Mocks generated by Mockito 5.4.4 from annotations\n// in app/test/a_test.dart.\n// Do not manually edit this file.\n',
        '/*\n * This file is automatically generated,\n * so please do not edit it.\n */\n',
        '// Code generated by tool. DO NOT EDIT.\n',
      ]) {
        expect(
          isGeneratedBanner('${banner}class A {}\n'),
          isTrue,
          reason: banner,
        );
      }
    });

    test('reads only the leading non-doc comments', () {
      for (final source in [
        'class A {}\n// GENERATED CODE. DO NOT EDIT.\n',
        '/// Do not edit the generated files under lib/gen.\nlibrary;\n',
        '// Copyright 2026. Do not redistribute.\nclass A {}\n',
        "const s = 'Generated code. Do not modify.';\n",
        '// Generated files go to lib/gen.\nclass A {}\n',
      ]) {
        expect(isGeneratedBanner(source), isFalse, reason: source);
      }
    });
  });
}
