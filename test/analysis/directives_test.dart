import 'package:ciach/src/analysis/directives.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('directivesIn', () {
    /// A [Directive] of [kind] that names [uris], and has an `if (…)` clause
    /// when [isConditional].
    Matcher isDirective(
      DirectiveKind kind,
      List<String> uris, {
      bool isConditional = false,
    }) => isA<Directive>()
        .having((it) => it.kind, 'kind', kind)
        .having((it) => it.uris, 'uris', uris)
        .having((it) => it.isConditional, 'isConditional', isConditional);

    test('reads each import, export and part, but no library directive', () {
      expect(
        directivesIn('''
library;

import 'a.dart';
export 'b.dart';
part 'c.dart';
'''),
        [
          isDirective(.import, ['a.dart']),
          isDirective(.export, ['b.dart']),
          isDirective(.part, ['c.dart']),
        ],
      );
    });

    test('reads a part-of directive with a URI, and one with a name', () {
      expect(directivesIn("part of 'owner.dart';"), [
        isDirective(.partOf, ['owner.dart']),
      ]);
      expect(directivesIn('part of my.lib;'), [isDirective(.partOf, [])]);
    });

    test('lists the default URI first, then the URI of each condition', () {
      expect(
        directivesIn('''
import 'io.dart'
    if (dart.library.io == 'true') 'native.dart'
    if (dart.library.js_interop) 'web.dart';
'''),
        [
          isDirective(.import, [
            'io.dart',
            'native.dart',
            'web.dart',
          ], isConditional: true),
        ],
      );
    });

    test('skips a directive in a comment', () {
      expect(directivesIn("// import 'gone.dart';\nimport 'a.dart';"), [
        isDirective(.import, ['a.dart']),
      ]);
    });

    test('starts at the doc comment or annotation, and ends after the `;`', () {
      const source = '''
/// Why.
@deprecated
import 'a.dart'; // c
''';
      final [directive] = directivesIn(source);

      expect((directive.start, directive.end), (0, source.indexOf(';') + 1));
    });

    test('lets through what every `show` clause shows, and none hides', () {
      final [filtered, plain] = directivesIn('''
export 'a.dart' show A, B hide B show B, C;
export 'b.dart';
''');

      expect(filtered.shown, {'B'});
      expect(filtered.hidden, {'B'});
      expect(plain.shown, isNull);
      expect(plain.hidden, isEmpty);
    });

    test('resolves the files that it names, and skips other schemes', () {
      final lib = p.join(p.rootPrefix(p.current), 'app', 'lib');
      final [directive, sdk] = directivesIn('''
import 'a.dart' if (dart.library.io) 'src/b.dart';
import 'dart:async';
''');

      expect(directive.pathsFrom(p.join(lib, 'main.dart'), .new()), [
        p.join(lib, 'a.dart'),
        p.join(lib, 'src', 'b.dart'),
      ]);
      expect(sdk.pathsFrom(p.join(lib, 'main.dart'), .new()), isEmpty);
    });
  });

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
