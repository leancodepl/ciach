@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/public_api.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  String path(String relative) => p.normalize(p.join(root.path, relative));

  setUp(() {
    root = .systemTemp.createTempSync('ciach_public_api_');
    write('pubspec.yaml', '''
name: lib_pkg
version: 1.0.0
environment:
  sdk: ^3.10.0
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  group('PublicApi.scan', () {
    test('every library under lib/ outside lib/src/ is public', () {
      write('lib/lib_pkg.dart', 'void a() {}');
      write('lib/extra/more.dart', 'void b() {}');
      write('lib/src/hidden.dart', 'void c() {}');
      write('bin/tool.dart', 'void d() {}');

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/lib_pkg.dart'), 'a'), isTrue);
      expect(api.exposes(path('lib/extra/more.dart'), 'b'), isTrue);
      expect(api.exposes(path('lib/src/hidden.dart'), 'c'), isFalse);
      expect(api.exposes(path('bin/tool.dart'), 'd'), isFalse);
    });

    test('exports are followed transitively through show and hide', () {
      write('lib/a.dart', '''
// export 'src/commented.dart';
export 'src/shown.dart' show A;
export 'package:lib_pkg/src/hidden.dart' hide H;
export 'src/chain.dart' show D, E, F;
export 'src/stub.dart' if (dart.library.io) 'src/io.dart';
''');
      write('lib/b.dart', "export 'src/shown.dart' show B;");
      write('lib/src/chain.dart', "export 'deep.dart' hide E;");
      write('lib/src/deep.dart', "export 'chain.dart';");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/commented.dart'), 'X'), isFalse);
      expect(api.exposes(path('lib/src/shown.dart'), 'A'), isTrue);
      expect(api.exposes(path('lib/src/shown.dart'), 'B'), isTrue);
      expect(api.exposes(path('lib/src/shown.dart'), 'C'), isFalse);
      expect(api.exposes(path('lib/src/hidden.dart'), 'H'), isFalse);
      expect(api.exposes(path('lib/src/hidden.dart'), 'G'), isTrue);
      expect(api.exposes(path('lib/src/deep.dart'), 'D'), isTrue);
      expect(api.exposes(path('lib/src/deep.dart'), 'E'), isFalse);
      expect(api.exposes(path('lib/src/deep.dart'), 'G'), isFalse);
      expect(api.exposes(path('lib/src/io.dart'), 'f'), isTrue);
    });

    test('a part shares its library visibility', () {
      write('lib/lib_pkg.dart', "part 'src/part.dart';");
      write('lib/src/part.dart', "part of '../lib_pkg.dart';");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/part.dart'), 'A'), isTrue);
    });

    test('a nested package has its own public libraries', () {
      write('example/pubspec.yaml', 'name: example_app');
      write(
        'example/lib/main.dart',
        "export 'package:example_app/src/a.dart';",
      );
      write('example/lib/src/b.dart', 'void b() {}');
      write('example/bin/run.dart', 'void run() {}');

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('example/lib/main.dart'), 'plugin'), isTrue);
      expect(api.exposes(path('example/lib/src/a.dart'), 'A'), isTrue);
      expect(api.exposes(path('example/lib/src/b.dart'), 'b'), isFalse);
      expect(api.exposes(path('example/bin/run.dart'), 'run'), isFalse);
    });

    test('packages sharing a name all have public libraries', () {
      write('a/pubspec.yaml', 'name: twin');
      write('a/lib/a.dart', 'void a() {}');
      write('b/pubspec.yaml', 'name: twin');
      write('b/lib/b.dart', 'void b() {}');

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('a/lib/a.dart'), 'a'), isTrue);
      expect(api.exposes(path('b/lib/b.dart'), 'b'), isTrue);
    });
  });
}
