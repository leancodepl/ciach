@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// Two packages side by side, neither using its own API: `published` can be
/// published, so its importers are elsewhere, and `internal` has
/// `publish_to: none`, so they would all be here.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_auto_exported_');
    write(
      'published/.dart_tool/package_config.json',
      packageConfig({'published': '.'}),
    );
    write('published/pubspec.yaml', '''
name: published
environment: {sdk: ^3.10.0}
''');
    write('published/lib/published.dart', 'void publishedApi() {}');
    write('published/lib/src/hidden.dart', 'void publishedInternals() {}');
    write(
      'internal/.dart_tool/package_config.json',
      packageConfig({'internal': '.'}),
    );
    write('internal/pubspec.yaml', '''
name: internal
publish_to: none
environment: {sdk: ^3.10.0}
''');
    write('internal/lib/internal.dart', 'void internalApi() {}');
    // A workspace root has no API, so no verdict either.
    write('pubspec.yaml', 'name: _');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  Future<Set<String>> unused({bool? includeExported}) async {
    final result = await Ciach(
      .new(rootPath: root.path, includeExported: includeExported),
    ).run();
    return {for (final d in result.unused) d.name};
  }

  test(
    "by default, only a publishable package's exported API is left out",
    () async {
      final lines = <String>[];
      final level = Logger.root.level;
      Logger.root.level = .CONFIG;
      final logging = Logger.root.onRecord
          .where((r) => r.loggerName == 'ciach.finder')
          .listen((r) => lines.add(r.message));
      addTearDown(() {
        Logger.root.level = level;
        return logging.cancel();
      });

      expect(await unused(), {'publishedInternals', 'internalApi'});
      expect(
        lines,
        containsAll(const [
          'internal has `publish_to: none`: its API is checked.',
          'published can be published: its exported API is left out (`--exported` checks it).',
        ]),
      );
      expect(lines, isNot(contains(startsWith('The scanned package'))));
    },
  );

  test('--exported checks every API', () async {
    expect(await unused(includeExported: true), {
      'publishedApi',
      'publishedInternals',
      'internalApi',
    });
  });

  test('--no-exported leaves out every API', () async {
    expect(await unused(includeExported: false), {'publishedInternals'});
  });
}
