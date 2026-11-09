/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:test/test.dart';

import '../support/previews_package.dart';
import '../support/test_package.dart';

void main() {
  late TestPackage package;

  setUpAll(() => package = previewsPackage());

  tearDownAll(() => package.dispose());

  Map<int, List<T>> byLine<T>(String source, Map<Position, T> byPosition) => {
    for (final (line, _) in source.split('\n').indexed)
      line: [
        for (final MapEntry(key: position, :value) in byPosition.entries)
          if (position.line == line) value,
      ],
  };

  /// The class [type] from the package `app` that an annotation creates,
  /// whose supertypes are [supertypes] and `Object`.
  AnnotationClass annotationClass(String type, List<String> supertypes) => .new(
    app(type),
    {for (final supertype in supertypes) app(supertype), object},
  );

  test(
    'resolves the class of each annotation that calls a constructor, with all its supertypes, and of no annotation that reads a constant',
    () async {
      const source = '''
import 'previews.dart';
import 'previews.dart' as previews;

@Preview() void a() {}
@DarkPreview() void b() {}
@ThemedPreview() void c() {}
@previews.DarkPreview() void d() {}
@Preview.named() void e() {}
@preview void f() {}
@override void g() {}
void h() {}
@Typed<int>() void i() {}
@AliasPreview() void j() {}
@previews.AliasOfAlias() void k() {}
@AliasTyped<int>() void l() {}
@Typed<AliasPreview>() void m() {}
@Holder.held void n() {}
@previews.preview void o() {}
@sameAsPreview void p() {}
@heldPreview void q() {}
@previewList void r() {}
@previews.Preview.named() void s() {}
@previews.Holder.held void t() {}
''';
      final file = await package.resolveNew(source);

      expect(
        byLine(source, {
          for (final MapEntry(key: name, value: annotations)
              in file.annotations.entries)
            for (final annotation in annotations)
              name: ?annotation.createdClass,
        }),
        {
          0: isEmpty,
          1: isEmpty,
          2: isEmpty,
          3: [annotationClass('Preview', [])],
          4: [
            annotationClass('DarkPreview', ['Preview']),
          ],
          5: [
            annotationClass('ThemedPreview', [
              'Themed',
              'DarkPreview',
              'Preview',
            ]),
          ],
          6: [
            annotationClass('DarkPreview', ['Preview']),
          ],
          7: [annotationClass('Preview', [])],
          8: isEmpty,
          9: isEmpty,
          10: isEmpty,
          // The name of a generic class has no type parameters.
          11: [
            annotationClass('Typed', ['Preview']),
          ],
          // A typedef stands for the class that it names.
          12: [
            annotationClass('DarkPreview', ['Preview']),
          ],
          13: [
            annotationClass('DarkPreview', ['Preview']),
          ],
          14: [
            annotationClass('Typed', ['Preview']),
          ],
          // A typedef in the type arguments is not the annotation's class.
          15: [
            annotationClass('Typed', ['Preview']),
          ],
          // A static constant, not a constructor of `Holder`.
          16: isEmpty,
          17: isEmpty,
          18: isEmpty,
          19: isEmpty,
          20: isEmpty,
          // A named constructor of a prefixed class.
          21: [annotationClass('Preview', [])],
          // A static constant of a prefixed class.
          22: isEmpty,
          23: isEmpty,
        },
      );
    },
  );

  test(
    'keys the annotations of a declaration by the start of its name, and names each after its `@` and import prefix',
    () async {
      const source = '''
import 'previews.dart' as previews;

@previews.Preview.named() void a() {}
''';
      final file = await package.resolveNew(source);

      expect(file.annotations, {
        Position(line: 2, character: source.split('\n')[2].indexOf('a()')): [
          DeclarationAnnotation(
            'Preview',
            package: 'app',
            createdClass: annotationClass('Preview', []),
          ),
        ],
      });
    },
  );

  test(
    'reads the first argument of an annotation when it is a string without interpolation, and gives every variable of a statement its annotations',
    () async {
      const source = r'''
import 'dart:core' as core;

@pragma('vm:entry-point') void a() {}
@core.pragma("vm:entry-point") void b() {}
@pragma(r'vm:entry-point', 'call') void c() {}
@pragma('vm:' 'entry-point') void d() {}
@pragma('dart2js:noInline', 'vm:entry-point') void e() {}
@pragma('vm:${1}') void f() {}
@override void g() {}
@pragma('vm:entry-point') int h = 0, i = 0;
''';
      final file = await package.resolveNew(source);

      expect(
        byLine(source, {
          for (final MapEntry(key: name, value: annotations)
              in file.annotations.entries)
            name: annotations.single.argument,
        }),
        {
          0: isEmpty,
          1: isEmpty,
          2: ['vm:entry-point'],
          3: ['vm:entry-point'],
          4: ['vm:entry-point'],
          5: ['vm:entry-point'],
          6: ['dart2js:noInline'],
          7: [null],
          8: [null],
          9: ['vm:entry-point', 'vm:entry-point'],
          10: isEmpty,
        },
      );
    },
  );

  test(
    'resolves the package that declares every annotation: a package by its name, an SDK library by its URI',
    () async {
      const source = '''
import 'dart:core' as core;
import 'dart:js_interop' as js;
import 'local.dart' as local;

@core.pragma('vm:entry-point') void a() {}
@js.JSExport() class B {}
@local.JSExport() class C {}
@core.Deprecated('x') void d() {}
void e() {}
''';
      final file = await package.resolveNew(source);

      expect(
        byLine(source, {
          for (final MapEntry(key: name, value: annotations)
              in file.annotations.entries)
            name: annotations.single.package,
        }),
        {
          0: isEmpty,
          1: isEmpty,
          2: isEmpty,
          3: isEmpty,
          4: ['dart:core'],
          5: ['dart:js_interop'],
          6: ['app'],
          7: ['dart:core'],
          8: isEmpty,
          9: isEmpty,
        },
      );
    },
  );
}
