/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/test_package.dart';

void main() {
  late TestPackage package;

  setUpAll(() {
    package = .new('resolved_files')
      ..writeAll({
        'pubspec.yaml': 'name: app\n',
        'lib/previews.dart': '''
class Preview {
  const Preview();
  const Preview.named();
}

class DarkPreview extends Preview {
  const DarkPreview();
}

mixin Themed {}

class ThemedPreview with Themed implements DarkPreview {
  const ThemedPreview();
}

const preview = Preview();

const sameAsPreview = preview;

const heldPreview = Holder.held;

const previewList = [Preview()];

class Typed<T> extends Preview {
  const Typed();
}

typedef AliasPreview = DarkPreview;

typedef AliasOfAlias = AliasPreview;

typedef AliasTyped<T extends Object> = Typed<T>;

class Holder {
  static const held = DarkPreview();
}
''',
        'lib/local.dart': '''
class JSExport {
  const JSExport();
}
''',
      });
  });

  tearDownAll(() => package.dispose());

  /// Writes [source] to a new file in the directory [dir] of the package, and
  /// resolves it.
  Future<ResolvedFile> resolve(String source, {String dir = 'lib'}) async =>
      (await package.files.of(package.writeNew(source, dir: dir)))!;

  /// Whether the signature of each of the [functions] that [source] declares
  /// is dynamic, by name.
  Future<Map<String, bool?>> dynamicSignatures(
    String source,
    List<String> functions,
  ) async {
    final path = package.writeNew(source);
    await package.files.of(path);
    return {
      for (final name in functions)
        name: package.files.hasDynamicSignature(
          path,
          positionOfName(path, name),
        ),
    };
  }

  /// The values of [byPosition] on each line of [source].
  Map<int, List<T>> byLine<T>(String source, Map<Position, T> byPosition) => {
    for (final (line, _) in source.split('\n').indexed)
      line: [
        for (final MapEntry(key: position, :value) in byPosition.entries)
          if (position.line == line) value,
      ],
  };

  const object = ResolvedClass('Object', 'dart:core');
  ResolvedClass app(String name) => .new(name, 'app');

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
      final file = await resolve(source);

      expect(byLine(source, file.annotationClasses), {
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
      });
    },
  );

  test(
    'keys an annotation by the name after its `@` and import prefix',
    () async {
      const source = '''
import 'previews.dart' as previews;

@previews.Preview.named() void a() {}
''';
      final file = await resolve(source);

      expect(file.annotationClasses.keys, [
        Position(line: 2, character: source.split('\n')[2].indexOf('Preview')),
      ]);
    },
  );

  test(
    'resolves the supertypes of each class and mixin, and of nothing else',
    () async {
      final file = await resolve('''
import 'previews.dart';

class Shown extends DarkPreview {
  const Shown();
}

class Implementing implements Preview {}

mixin Themed {}

class Mixing with Themed {}

class Bounded<T extends num> {}

class Plain {}

class Applied = Preview with Themed;

enum Color { red }

extension type Id(int value) {}

void notAClass() {}
''');

      expect(
        {
          for (final symbol in file.symbols)
            symbol.name: file.supertypes[symbol.selectionRange.start],
        },
        {
          'Shown': {app('DarkPreview'), app('Preview'), object},
          'Implementing': {app('Preview'), object},
          'Themed': {object},
          'Mixing': {app('Themed'), object},
          'Bounded': {object},
          'Plain': {object},
          'Applied': {app('Preview'), app('Themed'), object},
          'Color': isNull,
          'Id': isNull,
          'notAClass': isNull,
        },
      );
    },
  );

  test(
    'lists the classes whose superclass has no unnamed constructor that takes no arguments',
    () async {
      const source = '''
class NoArguments {
  NoArguments({int? x});
}

class Positional {
  Positional(int x);
}

class RequiredNamed {
  RequiredNamed({required int x});
}

class OnlyNamed {
  OnlyNamed.named();
}

class Implicit {}

class A extends NoArguments {}

class B extends Positional {}

class C extends RequiredNamed {}

class D extends OnlyNamed {}

class E extends Implicit {}

class F {}
''';
      final file = await resolve(source);

      expect(
        [
          for (final position in file.needSuperArguments)
            source.split('\n')[position.line],
        ],
        unorderedEquals([
          'class B extends Positional {}',
          'class C extends RequiredNamed {}',
          'class D extends OnlyNamed {}',
        ]),
      );
    },
  );

  test(
    'gives a class in a file outside `lib/` the package whose root holds the file',
    () async {
      final file = await resolve('''
class Base {}

class Derived extends Base {}
''', dir: 'test');

      expect(file.supertypes.values.last, {app('Base'), object});
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
      final file = await resolve(source);

      expect(byLine(source, file.annotationPackages), {
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
      });
    },
  );

  test(
    'gives the first compile error of a file, and none for a file without one',
    () async {
      final broken = await resolve('''
void a() {}

void b() => missing();

void c() => alsoMissing();
''');
      final valid = await resolve('void a() {}\n');

      // The wording of the message differs between analyzer versions.
      expect(
        broken.firstError?.position,
        const Position(line: 2, character: 12),
      );
      expect(broken.firstError?.message, contains("'missing'"));
      expect(valid.firstError, isNull);
    },
  );

  test(
    'a signature is dynamic when a parameter or the return type is `dynamic` or a bare `Function`, also when it is omitted, or holds one',
    () async {
      expect(
        await dynamicSignatures(
          '''
void untyped(cb) {}
omitted() => 0;
void listed(List<dynamic> values) {}
void callback(void Function(Function) f) {}
(int, {dynamic x}) record() => (1, x: 2);
Function? bare() => null;
''',
          ['untyped', 'omitted', 'listed', 'callback', 'record', 'bare'],
        ),
        {
          'untyped': true,
          'omitted': true,
          'listed': true,
          'callback': true,
          'record': true,
          'bare': true,
        },
      );
    },
  );

  test(
    'a signature with only other types is not dynamic, and a variable has none',
    () async {
      expect(
        await dynamicSignatures(
          '''
void precise(int x, void Function(int) f) {}
Object? get getter => null;

class Box {
  Box.sized(int size);

  void fill(List<Object?> values) {}
}

int variable = 0;
''',
          ['precise', 'getter', 'sized', 'fill', 'variable'],
        ),
        {
          'precise': false,
          'getter': false,
          'sized': false,
          'fill': false,
          'variable': null,
        },
      );
    },
  );

  test('returns `null` for a path that is not absolute', () async {
    expect(await package.files.of('lib/local.dart'), isNull);
  });
}
