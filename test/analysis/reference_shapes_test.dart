/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/test_package.dart';

/// The answers that `ResolvedFiles` gives about the code at a reference,
/// from the AST that `reference_shapes.dart` reads.
void main() {
  late TestPackage package;

  setUpAll(() => package = .new('reference_shapes'));

  tearDownAll(() => package.dispose());

  /// A `/*label*/` comment right before the name that a test asks about.
  final marker = RegExp(r'/\*(?<label>\w+)\*/');

  /// Writes [source] to a new file and returns its path, with the offset of
  /// each name that a [marker] marks in [source], by its label.
  (String, Map<String, int>) marked(String source) => (
    package.writeNew(source),
    {
      for (final match in marker.allMatches(source))
        match.namedGroup('label')!: match.end,
    },
  );

  /// Writes [source] to a new file and returns the answer of [question] at
  /// each name that a [marker] marks in [source], by its label.
  Map<String, bool> answers(
    String source,
    bool Function(Location location) question,
  ) {
    final (path, positions) = marked(source);
    return {
      for (final MapEntry(key: label, value: position) in positions.entries)
        label: question(
          .new(
            path: path,
            range: .new(start: position, end: position),
          ),
        ),
    };
  }

  test(
    'a reference in a doc comment is a doc reference, also after code on the same line, and one in code or in another comment is not',
    () {
      final path = package.writeNew('''
/// Uses [Shape] and [Shape.area].
class Shape {
  // Not a doc comment: [Shape].
  int area() => 0;
}

Shape make() => Shape();

int count = 0; /// See [Shape].
int total = 0;
''');

      expect(
        [
          for (final occurrence in [0, 1, 2, 3, 4, 5, 6])
            package.files.isDocReference(
              .new(
                path: path,
                range: .new(
                  start: offsetOfName(path, 'Shape', occurrence: occurrence),
                  end: offsetOfName(path, 'Shape', occurrence: occurrence),
                ),
              ),
            ),
        ],
        [true, true, false, false, false, false, true],
      );
    },
  );

  test(
    'the type of the pattern of a case, a guarded case, an if-case or a switch-expression arm is a type pattern, and a nested pattern, a pattern variable declaration or a construction is not',
    () {
      expect(
        answers('''
sealed class Shape {}

class Circle extends Shape {}

class Box extends Shape {
  Box(this.inner);

  final Shape inner;
}

int area(Shape shape) {
  switch (shape) {
    case /*object*/Circle():
      return 1;
    case Box(inner: /*nested*/Circle()):
      return 2;
    case /*guarded*/Box box when box.inner is Circle:
      return 3;
    default:
      return 0;
  }
}

int arm(Shape shape) => switch (shape) {
  /*arm*/Circle() => 1,
  _ => 0,
};

bool ifCase(Shape shape) {
  if (shape case /*ifCase*/Circle()) {
    return true;
  }
  return false;
}

Box unpack(Box box) {
  final /*declaration*/Box(:inner) = box;
  return Box(inner);
}

Shape build() => /*construction*/Circle();
''', package.files.isTypePattern),
        {
          'object': true,
          'nested': false,
          'guarded': true,
          'arm': true,
          'ifCase': true,
          'declaration': false,
          'construction': false,
        },
      );
    },
  );

  test(
    'an enum that `.values` follows is a values access, also with an import prefix, and the enum with another member or as a type is not',
    () {
      package.write('lib/colors.dart', 'enum Color { red }\n');

      expect(
        answers('''
import 'colors.dart';
import 'colors.dart' as colors;

final all = /*plain*/Color.values;
final first = /*chained*/Color.values.first;
final prefixed = colors./*prefixed*/Color.values;
final red = /*member*/Color.red;
final List</*type*/Color> none = [];
''', package.files.isEnumValuesAccess),
        {
          'plain': true,
          'chained': true,
          'prefixed': true,
          'member': false,
          'type': false,
        },
      );
    },
  );

  test(
    'the only type argument of `State` in an `extends` clause is a `State` type argument, and one of another class, of `implements`, of an annotation or of a `State` with two is not',
    () {
      package.write('lib/two.dart', 'class State<A, B> {}\n');

      expect(
        answers('''
import 'two.dart' as two;

class State<T> {}

class Other<T> {}

class Foo {}

class _A extends State</*paired*/Foo> {}

class _B extends Other</*other*/Foo> {}

class _C implements State</*implemented*/Foo> {}

class _D extends two.State</*twoArguments*/Foo, Foo> {}

State</*annotated*/Foo>? state;
''', package.files.isStateTypeArgument),
        {
          'paired': true,
          'other': false,
          'implemented': false,
          'twoArguments': false,
          'annotated': false,
        },
      );
    },
  );

  test(
    'a position in the body of a constructor, a method, a getter or a local function inside one is in the body, and one in a parameter or an initializer is not',
    () async {
      final (path, positions) = marked('''
class Box {
  Box(int size) : count = /*initializer*/size {
    print(/*constructorBody*/size);
  }

  int count;

  int method(int /*parameter*/x) {
    int inner() => /*local*/x;
    return /*methodBody*/inner();
  }

  int get doubled => /*getterBody*/count * 2;
}
''');
      final outline = (await package.files.of(path))!.outline;
      final members = outline.children.single.children;
      Range codeOf(OutlineKind kind) =>
          members.firstWhere((member) => member.element.kind == kind).codeRange;
      final declarations = {
        'initializer': codeOf(.constructor),
        'constructorBody': codeOf(.constructor),
        'parameter': codeOf(.method),
        'local': codeOf(.method),
        'methodBody': codeOf(.method),
        'getterBody': codeOf(.getter),
      };

      expect(
        {
          for (final MapEntry(key: label, value: declaration)
              in declarations.entries)
            label: package.files.isInBody(path, positions[label]!, declaration),
        },
        {
          'initializer': false,
          'constructorBody': true,
          'parameter': false,
          'local': true,
          'methodBody': true,
          'getterBody': true,
        },
      );
    },
  );
}
