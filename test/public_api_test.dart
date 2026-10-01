@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/models.dart';
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
    write(
      '.dart_tool/package_config.json',
      '{\n  "configVersion": 2,\n  "packages": [\n'
          '    { "name": "lib_pkg", "rootUri": "../", "packageUri": "lib/", '
          '"languageVersion": "3.10" }\n  ]\n}\n',
    );
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

    test('exports are followed through show and hide, transitively', () {
      write('lib/lib_pkg.dart', '''
// export 'src/commented.dart';
export 'src/shown.dart' show A, B;
export 'package:lib_pkg/src/hidden.dart' hide C;
export 'src/chain.dart' show D, E;
''');
      write('lib/src/chain.dart', "export 'deep.dart' hide E;");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/commented.dart'), 'X'), isFalse);
      expect(api.exposes(path('lib/src/shown.dart'), 'A'), isTrue);
      expect(api.exposes(path('lib/src/shown.dart'), 'Z'), isFalse);
      expect(api.exposes(path('lib/src/hidden.dart'), 'Z'), isTrue);
      expect(api.exposes(path('lib/src/hidden.dart'), 'C'), isFalse);
      expect(api.exposes(path('lib/src/deep.dart'), 'D'), isTrue);
      expect(api.exposes(path('lib/src/deep.dart'), 'E'), isFalse);
      expect(api.exposes(path('lib/src/deep.dart'), 'F'), isFalse);
    });

    test('a name exported by any route is exposed', () {
      write('lib/a.dart', "export 'src/x.dart' show A;");
      write('lib/b.dart', "export 'src/x.dart' show B;");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/x.dart'), 'A'), isTrue);
      expect(api.exposes(path('lib/src/x.dart'), 'B'), isTrue);
      expect(api.exposes(path('lib/src/x.dart'), 'C'), isFalse);
    });

    test('every branch of a conditional export counts', () {
      write(
        'lib/lib_pkg.dart',
        "export 'src/stub.dart' if (dart.library.io) 'src/io.dart' show f;",
      );

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/stub.dart'), 'f'), isTrue);
      expect(api.exposes(path('lib/src/io.dart'), 'f'), isTrue);
      expect(api.exposes(path('lib/src/io.dart'), 'g'), isFalse);
    });

    test('a part shares its library visibility', () {
      write('lib/lib_pkg.dart', "part 'src/part.dart';");
      write('lib/src/part.dart', "part of '../lib_pkg.dart';");
      write('lib/src/inner.dart', "part 'inner_part.dart';");
      write('lib/src/inner_part.dart', "part of 'inner.dart';");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/part.dart'), 'A'), isTrue);
      expect(api.exposes(path('lib/src/inner_part.dart'), 'A'), isFalse);
    });

    test('a cycle of exports terminates', () {
      write('lib/lib_pkg.dart', "export 'src/a.dart';");
      write('lib/src/a.dart', "export 'b.dart';");
      write('lib/src/b.dart', "export 'a.dart';");

      final api = PublicApi.scan(root.path);

      expect(api.exposes(path('lib/src/b.dart'), 'B'), isTrue);
    });
  });

  test('with includeExported off, only what other packages can name is '
      'left out', () async {
    write('lib/lib_pkg.dart', '''
export 'src/api.dart' show Api;

void publicTopLevel() {}
''');
    write('lib/src/api.dart', '''
class Api {
  void exportedMember() {}
}

class Internal {
  void internalMember() {}
}

void notExported() {}

void _private() {}
''');
    write('bin/main.dart', '''
void main() {}

void cliHelper() {}
''');

    Future<Set<String>> unused({required bool includeExported}) async {
      final result = await Ciach(
        FinderOptions(rootPath: root.path, includeExported: includeExported),
      ).run();
      return {for (final decl in result.unused) decl.qualifiedName};
    }

    final everything = await unused(includeExported: true);
    expect(everything, {
      'publicTopLevel',
      'Api.exportedMember',
      'Internal',
      'Internal.internalMember',
      'notExported',
      '_private',
      'cliHelper',
    });

    expect(await unused(includeExported: false), {
      'Internal',
      'Internal.internalMember',
      'notExported',
      '_private',
      'cliHelper',
    });
  });
}
