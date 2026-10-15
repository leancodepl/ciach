import 'package:ciach/src/source/directives.dart';
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
}
