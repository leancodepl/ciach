/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/analysis/language_versions.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:package_config/package_config.dart';
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/outlines.dart';
import '../support/test_package.dart';

/// The outline that `unitOutline` builds, read through `ResolvedFiles`, which
/// resolves the file first.
void main() {
  late TestPackage package;

  setUpAll(() {
    package = .new('unit_outline', languageVersion: '$newestLanguageVersion')
      // A library whose file name ends with `test.dart` declares the `test`
      // and `group` functions that the outline lists calls of.
      ..write('lib/fake_test.dart', '''
void test(String description, void Function() body) {}

void group(String description, void Function() body) {}
''');
  });

  tearDownAll(() => package.dispose());

  /// Writes [source] to a new file and returns its outline.
  Future<Outline> outlineOf(String source) async =>
      (await package.files.of(package.writeNew(source)))!.outline;

  /// The declarations in [outline], in order, each with how deep it is
  /// nested, its kind, its name and the text of its name range in [source].
  List<(int, OutlineKind, String, String?)> declarationsIn(
    String source,
    Outline outline,
  ) => [
    for (final child in outline.children) ...[
      (
        0,
        child.element.kind,
        child.element.name,
        child.element.range?.let((range) => textIn(source, range)),
      ),
      for (final (depth, kind, name, nameText) in declarationsIn(source, child))
        (depth + 1, kind, name, nameText),
    ],
  ];

  test(
    'lists each declaration with its kind and name, and the members of each type',
    () async {
      const source = '''
class Shape<T> {
  Shape();
  Shape.named();
  factory Shape.make() => Shape();
  final int size = 0, other = 1;
  static int count = 0;
  int get area => 0;
  set area(int value) {}
  int operator +(Shape<T> other) => 0;
  void draw() {}
}

mixin Movable {}

enum Color {
  red,
  green;

  void paint() {}
}

extension Shout on String {
  String shout() => toUpperCase();
}

extension<T> on List<T> {}

extension type Id(int value) {
  int get twice => value * 2;
}

int top = 0, bottom = 1;

void run() {}

int get answer => 42;

set answer(int value) {}

class Mixed = Shape<int> with Movable;

typedef void Callback(int value);

typedef Compare<T> = int Function(T a, T b);

typedef Ints = List<int>;
''';
      final outline = await outlineOf(source);

      expect(declarationsIn(source, outline), [
        (0, OutlineKind.class$, 'Shape', 'Shape'),
        (1, OutlineKind.constructor, 'Shape', 'Shape'),
        (1, OutlineKind.constructor, 'Shape.named', 'named'),
        (1, OutlineKind.constructor, 'Shape.make', 'make'),
        (1, OutlineKind.field, 'size', 'size'),
        (1, OutlineKind.field, 'other', 'other'),
        (1, OutlineKind.field, 'count', 'count'),
        (1, OutlineKind.getter, 'area', 'area'),
        (1, OutlineKind.setter, 'area', 'area'),
        (1, OutlineKind.method, '+', '+'),
        (1, OutlineKind.method, 'draw', 'draw'),
        (0, OutlineKind.mixin, 'Movable', 'Movable'),
        (0, OutlineKind.enum$, 'Color', 'Color'),
        (1, OutlineKind.enumConstant, 'red', 'red'),
        (1, OutlineKind.enumConstant, 'green', 'green'),
        (1, OutlineKind.method, 'paint', 'paint'),
        (0, OutlineKind.extension, 'Shout', 'Shout'),
        (1, OutlineKind.method, 'shout', 'shout'),
        // An unnamed extension is named after its `on` type.
        (0, OutlineKind.extension, 'extension on List<T>', 'List<T>'),
        (0, OutlineKind.extensionType, 'Id', 'Id'),
        (1, OutlineKind.getter, 'twice', 'twice'),
        (0, OutlineKind.topLevelVariable, 'top', 'top'),
        (0, OutlineKind.topLevelVariable, 'bottom', 'bottom'),
        (0, OutlineKind.function, 'run', 'run'),
        (0, OutlineKind.getter, 'answer', 'answer'),
        (0, OutlineKind.setter, 'answer', 'answer'),
        (0, OutlineKind.classTypeAlias, 'Mixed', 'Mixed'),
        (0, OutlineKind.functionTypeAlias, 'Callback', 'Callback'),
        (0, OutlineKind.functionTypeAlias, 'Compare', 'Compare'),
        (0, OutlineKind.typeAlias, 'Ints', 'Ints'),
      ]);
    },
  );

  test(
    'gives parameters, type parameters and the return type of a function or method as written',
    () async {
      final outline = await outlineOf('''
class Box<T extends num> {
  Box(T value, {int? size});
  R map<R>(R Function(T) f) => throw 0;
  int get size => 0;
}

void log(String message, [int level = 0]) {}

get untyped => 0;

typedef void Callback(int value);

typedef Compare<T> = int Function(T a, T b);

typedef Ints = List<int>;
''');

      expect(
        [
          for (final node in nestedIn(outline))
            (
              node.element.name,
              node.element.parameters,
              node.element.typeParameters,
              node.element.returnType,
            ),
        ],
        [
          ('Box', null, '<T extends num>', null),
          ('Box', '(T value, {int? size})', null, null),
          ('map', '(R Function(T) f)', '<R>', 'R'),
          ('size', null, null, 'int'),
          ('log', '(String message, [int level = 0])', null, 'void'),
          ('untyped', '', null, ''),
          ('Callback', '(int value)', null, null),
          ('Compare', '(T a, T b)', '<T>', null),
          ('Ints', null, null, null),
        ],
      );
    },
  );

  test(
    "a declaration's range includes its doc comment and annotations, and its code range doesn't",
    () async {
      const source = '''
/// Docs.
@deprecated
void f() {}
''';
      final outline = await outlineOf(source);

      final f = outline.children.single;
      expect(textIn(source, f.range), source.trimRight());
      expect(textIn(source, f.codeRange), 'void f() {}');
    },
  );

  test(
    'the range of the first variable of a declaration starts with the declaration, and the range of the last ends with it',
    () async {
      const source = '''
/// Docs.
final int a = 1, b = 2, c = 3;
''';
      final outline = await outlineOf(source);

      expect(
        [
          for (final variable in outline.children)
            (
              textIn(source, variable.range),
              textIn(source, variable.codeRange),
            ),
        ],
        [
          ('/// Docs.\nfinal int a = 1', 'a = 1'),
          ('b = 2', 'b = 2'),
          ('c = 3;', 'c = 3'),
        ],
      );
    },
  );

  test(
    'lists the local functions in a body, and the test and group calls with the declarations in each group',
    () async {
      const source = '''
import 'fake_test.dart';

void main() {
  void helper() {}
  group('outer', () {
    void inGroup() {}
    test('inner', () {
      void inTest() {}
    });
  });
  final run = (void Function() body) => body();
  run(() {
    void inClosure() {}
  });
  undefined(() {
    void inUndefined() {}
  });
}
''';
      final outline = await outlineOf(source);

      expect(declarationsIn(source, outline), [
        (0, OutlineKind.function, 'main', 'main'),
        (1, OutlineKind.function, 'helper', 'helper'),
        (1, OutlineKind.unitTestGroup, 'group', 'group'),
        (2, OutlineKind.function, 'inGroup', 'inGroup'),
        // A test lists nothing that its closure declares.
        (2, OutlineKind.unitTestTest, 'test', 'test'),
        (1, OutlineKind.function, 'inClosure', 'inClosure'),
        // The arguments of a call that resolves to nothing are skipped.
      ]);
    },
  );

  test(
    'lists a primary constructor, the fields that its declaring parameters declare, and its body part, and names constructors that `new` and `factory` declare after their class',
    () async {
      const source = '''
class Point(var int x, final int y, int z) {
  this : assert(z > 0);
}

class Money.cents(final int amount);

class Registry {
  new();
  new named();
  factory make() => Registry();
}
''';
      final outline = await outlineOf(source);

      expect(declarationsIn(source, outline), [
        (0, OutlineKind.class$, 'Point', 'Point'),
        (1, OutlineKind.constructor, 'Point', 'Point'),
        (1, OutlineKind.field, 'x', 'x'),
        (1, OutlineKind.field, 'y', 'y'),
        (1, OutlineKind.constructor, 'this', 'this'),
        (0, OutlineKind.class$, 'Money', 'Money'),
        // The name range of a named primary constructor starts at its `.`.
        (1, OutlineKind.constructor, 'Money.cents', '.cents'),
        (1, OutlineKind.field, 'amount', 'amount'),
        (0, OutlineKind.class$, 'Registry', 'Registry'),
        (1, OutlineKind.constructor, 'Registry', 'new'),
        (1, OutlineKind.constructor, 'Registry.named', 'named'),
        (1, OutlineKind.constructor, 'Registry.make', 'make'),
      ]);
    },
    skip: newestLanguageVersion < LanguageVersion(3, 13)
        ? 'This analyzer does not support Dart 3.13 constructors.'
        : false,
  );

  test(
    'the `this` of the body of a primary constructor names the constructor, whose signature it reads',
    () async {
      final path = package.writeNew('''
class Holder(dynamic value) {
  this {
    print(value);
  }
}
''');
      await package.files.of(path);

      expect(
        package.files.hasDynamicSignature(path, positionOfName(path, 'this')),
        isTrue,
      );
    },
    skip: newestLanguageVersion < LanguageVersion(3, 13)
        ? 'This analyzer does not support Dart 3.13 constructors.'
        : false,
  );

  /// The names of the declarations in [outline] that [test] holds for.
  Set<String> namesWhere(Outline outline, bool Function(OutlineElement) test) =>
      {
        for (final node in nestedIn(outline))
          if (test(node.element)) node.element.name,
      };

  test(
    'marks a redirecting factory, and neither a factory with a body nor a generative constructor',
    () async {
      final outline = await outlineOf('''
class Shape {
  Shape();
  factory Shape.circle() = Circle;
  factory Shape.square() => Circle();
  factory Shape.empty() {
    return Circle();
  }
}

class Circle extends Shape {}
''');

      expect(namesWhere(outline, (element) => element.isRedirectingFactory), {
        'Shape.circle',
      });
    },
  );

  test(
    'marks a primary constructor and the fields of its declaring parameters as in the header of their class, and no member of its body',
    () async {
      final outline = await outlineOf('''
class Point(var int x, final int y, int z) {
  final int w = 0;
  this : assert(z > 0);
  Point.origin() : this(0, 0, 1);
}
''');

      expect(namesWhere(outline, (element) => element.isInTypeHeader), {
        'Point',
        'x',
        'y',
      });
    },
    skip: newestLanguageVersion < LanguageVersion(3, 13)
        ? 'This analyzer does not support Dart 3.13 constructors.'
        : false,
  );

  test(
    'marks the final instance fields in the body of a class, also the later variables of a statement, and no static, const or other field',
    () async {
      final outline = await outlineOf('''
class Fields {
  final int a = 0, b = 1;
  late final int c;
  int d = 0;
  static final int e = 0;
  static const int f = 0;
  var g = 0;
}

final int top = 0;
''');

      expect(namesWhere(outline, (element) => element.isFinalInstanceField), {
        'a',
        'b',
        'c',
      });
    },
  );

  test(
    "marks an enum that reads its own `values` in its body, with or without its name, and no enum that reads only a parameter named `values` or another enum's `values`",
    () async {
      final outline = await outlineOf('''
enum Bare {
  a;
  static Bare first() => values.first;
}

enum Passed {
  a;
  static int count() => countOf(values);
}

enum Qualified {
  a;
  static List<Qualified> all() => Qualified.values;
}

enum Local {
  a;
  static int sum(List<int> values) => values.length;
}

enum Other {
  a;
  static int count() => Bare.values.length;
}

int countOf(List<Object> values) => values.length;
''');

      expect(namesWhere(outline, (element) => element.usesOwnValues), {
        'Bare',
        'Passed',
        'Qualified',
      });
    },
  );
}
