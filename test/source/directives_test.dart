import 'dart:io';

import 'package:ciach/src/source/directives.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('isDirectiveOnly', () {
    test('holds for nothing, whitespace and comments', () {
      expect(isDirectiveOnly(''), isTrue);
      expect(isDirectiveOnly(' \n\t\r\n'), isTrue);
      expect(
        isDirectiveOnly('''
// a
/* b /* nested */ c */
/// d'''),
        isTrue,
      );
    });

    test('holds for library, import and part-of directives', () {
      expect(
        isDirectiveOnly('''
// Copyright.
library;

import 'dart:async' show Future;
import r'raw.dart' as raw;
import "a.dart" if (dart.library.io) "b.dart";
'''),
        isTrue,
      );
      expect(isDirectiveOnly('library my.lib;'), isTrue);
      expect(isDirectiveOnly("part of 'owner.dart';"), isTrue);
      expect(isDirectiveOnly('part of my.lib;'), isTrue);
    });

    test(
      'reads past comments and semicolons in strings inside a directive',
      () {
        expect(isDirectiveOnly("import 'a.dart' // why\n  show A;"), isTrue);
        expect(isDirectiveOnly("import 'a;b.dart';"), isTrue);
      },
    );

    test('fails on anything else', () {
      expect(isDirectiveOnly('void f() {}'), isFalse);
      expect(isDirectiveOnly("import 'a.dart';\nconst x = 1;"), isFalse);
      expect(isDirectiveOnly("export 'a.dart';"), isFalse);
      expect(isDirectiveOnly("part 'a_part.dart';"), isFalse);
      expect(isDirectiveOnly('libraryX;'), isFalse);
      expect(isDirectiveOnly("import 'a.dart'"), isFalse);
      expect(isDirectiveOnly('import;'), isFalse);
    });
  });

  group('libraryOf and filesOfLibrary', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('ciach_parts_'));
    tearDown(() => dir.deleteSync(recursive: true));

    /// Writes [files], by name, into [dir] and returns their paths.
    Map<String, String> write(Map<String, String> files) => {
      for (final MapEntry(key: name, value: content) in files.entries)
        name: (File(p.join(dir.path, name))..writeAsStringSync(content)).path,
    };

    test('a part of a part belongs to the library at the top', () {
      final paths = write({
        'lib.dart': "part 'a.dart';",
        'a.dart': "part of 'lib.dart';\npart 'b.dart';",
        'b.dart': "part of 'a.dart';",
      });
      final packages = PackageResolver();

      expect(
        [for (final path in paths.values) libraryOf(path, packages)],
        [paths['lib.dart'], paths['lib.dart'], paths['lib.dart']],
      );
      expect(filesOfLibrary(paths['lib.dart']!, packages), {...paths.values});
    });

    test('a part that names its library by name has no known library', () {
      final paths = write({'a.dart': 'part of my.lib;'});

      expect(libraryOf(paths['a.dart']!, PackageResolver()), isNull);
    });

    test('`part of` directives that form a cycle have no library', () {
      final paths = write({
        'a.dart': "part of 'b.dart';",
        'b.dart': "part of 'a.dart';",
      });

      expect(libraryOf(paths['a.dart']!, PackageResolver()), isNull);
    });
  });
}
