/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/element_uses.dart';
import 'package:ciach/src/analysis/language_versions.dart';
import 'package:ciach/src/workspace/dart_executable.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

/// A use as the tests compare it: the kind and name of the declaration that
/// it uses, such as `new` for an unnamed constructor, and the text that it
/// covers.
typedef _Use = ({ElementKind kind, String name, String text});

void main() {
  late Directory tempDir;
  late AnalysisContextCollection collection;
  var written = 0;

  setUpAll(() {
    tempDir = .systemTemp.createTempSync('ciach_element_uses_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        packageConfig(
          {'app': '.'},
          languageVersions: {'app': '$newestLanguageVersion'},
        ),
      );
    File(p.join(tempDir.path, 'lib', 'shown.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
const shown = 1;

class Shown {}
''');
    collection = .new(
      includedPaths: [tempDir.path],
      sdkPath: sdkPathOf(findDartExecutable()),
    );
  });

  tearDownAll(() async {
    await collection.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// The uses in [source], written to a new file, of the package's own
  /// declarations of the [kinds].
  Future<List<_Use>> usesIn(String source, Set<ElementKind> kinds) async {
    final path = p.join(tempDir.path, 'lib', 'file${written++}.dart');
    File(path).writeAsStringSync(source);
    final result =
        await collection.contextFor(path).currentSession.getResolvedUnit(path)
            as ResolvedUnitResult;
    return [
      for (final (:element, :offset, :length) in elementUses(result.unit))
        if (kinds.contains(element.kind) &&
            element.library?.uri.scheme == 'package')
          (
            kind: element.kind,
            name: element.name!,
            text: source.substring(offset, offset + length),
          ),
    ];
  }

  test('a type is used where its name is written, after an import prefix', () {
    return expectLater(
      usesIn(
        '''
import 'shown.dart' as prefixed;

class Foo {}

Foo? a;
List<prefixed.Shown>? b;
''',
        {.CLASS},
      ),
      completion([
        (kind: ElementKind.CLASS, name: 'Foo', text: 'Foo'),
        (kind: ElementKind.CLASS, name: 'Shown', text: 'Shown'),
      ]),
    );
  });

  test(
    'a variable is used by its getter when read, by its setter when written, and by both in a compound assignment',
    () {
      return expectLater(
        usesIn(
          '''
int counter = 0;

void f() {
  counter = 1;
  print(counter);
  counter += 2;
  counter++;
}
''',
          {.GETTER, .SETTER},
        ),
        completion([
          (kind: ElementKind.SETTER, name: 'counter', text: 'counter'),
          (kind: ElementKind.GETTER, name: 'counter', text: 'counter'),
          (kind: ElementKind.GETTER, name: 'counter', text: 'counter'),
          (kind: ElementKind.SETTER, name: 'counter', text: 'counter'),
          (kind: ElementKind.GETTER, name: 'counter', text: 'counter'),
          (kind: ElementKind.SETTER, name: 'counter', text: 'counter'),
        ]),
      );
    },
  );

  test(
    'a constructor call covers `.name`, or nothing right after the type for the unnamed constructor',
    () {
      return expectLater(
        usesIn(
          '''
class Foo<T> {
  Foo();
  Foo.named();
  factory Foo.redirect() = Foo.named;
}

enum E {
  plain,
  called(),
  named.named();

  const E();
  const E.named();
}

void f() {
  Foo();
  Foo<int>.named();
  Foo.new;
  Foo<int> shorthand = .named();
}
''',
          {.CONSTRUCTOR},
        ),
        completion([
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: '.new'),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: 'named'),
        ]),
      );
    },
  );

  test(
    'an annotation calls its constructor right after the type arguments, or at the name of a named one',
    () {
      return expectLater(
        usesIn(
          '''
class Tag<T> {
  const Tag();
  const Tag.named();
}

@Tag()
@Tag<int>()
@Tag.named()
void f() {}
''',
          {.CONSTRUCTOR},
        ),
        completion([
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: 'named'),
        ]),
      );
    },
  );

  test(
    'a constructor calls the super constructor that it names, or the unnamed one when it names none',
    () {
      return expectLater(
        usesIn(
          '''
class Base {
  Base();
  Base.named();
}

class Implicit extends Base {}

class Explicit extends Base {
  Explicit() : super.named();
  Explicit.other();
  Explicit.redirect() : this();
}
''',
          {.CONSTRUCTOR},
        ),
        completion([
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: 'Implicit'),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: 'Explicit.other'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: ''),
        ]),
      );
    },
  );

  test(
    'a primary constructor calls the super constructor that its body names, or the unnamed one when it names none',
    () {
      return expectLater(
        usesIn(
          '''
class Base {
  Base();
  Base.named();
}

class Implicit(final int a) extends Base;

class Explicit.make(final int a) extends Base {
  this : super.named();
}
''',
          {.CONSTRUCTOR},
        ),
        completion([
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: 'Implicit'),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
        ]),
      );
    },
    skip: newestLanguageVersion < LanguageVersion(3, 13)
        ? 'This analyzer does not support Dart 3.13 constructors.'
        : false,
  );

  test(
    'a call of a constructor that a mixin application class forwards uses the superclass constructor',
    () {
      return expectLater(
        usesIn(
          '''
mixin M {}

class Base {
  Base.named();
}

class Mixed = Base with M;

void f() => Mixed.named();
''',
          {.CONSTRUCTOR},
        ),
        completion([
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
        ]),
      );
    },
  );

  test(
    'an operator is used at its token, `[]` and `[]=` at the bracket, and a compound assignment uses both and its operator',
    () {
      return expectLater(
        usesIn(
          '''
class V {
  V operator +(Object other) => this;
  V operator -() => this;
  V operator [](int i) => this;
  void operator []=(int i, V value) {}
  bool operator <(V other) => false;
}

void f(V a, V b) {
  a + b;
  -a;
  a[0];
  a[0] = b;
  a[0] += 1;
  if (a case < b) {}
}
''',
          {.METHOD},
        ),
        completion([
          (kind: ElementKind.METHOD, name: '+', text: '+'),
          (kind: ElementKind.METHOD, name: '-', text: '-'),
          (kind: ElementKind.METHOD, name: '[]', text: '['),
          (kind: ElementKind.METHOD, name: '[]=', text: '['),
          (kind: ElementKind.METHOD, name: '+', text: '+='),
          (kind: ElementKind.METHOD, name: '[]', text: '['),
          (kind: ElementKind.METHOD, name: '[]=', text: '['),
          (kind: ElementKind.METHOD, name: '<', text: '<'),
        ]),
      );
    },
  );

  test(
    'an object called like a function or used as one uses its `call` method',
    () {
      return expectLater(
        usesIn(
          '''
class Doubler {
  int call(int value) => value;
}

void f(Doubler doubler) {
  doubler(1);
  int Function(int) asFunction = doubler;
  doubler.call(2);
}
''',
          {.METHOD},
        ),
        completion([
          (kind: ElementKind.METHOD, name: 'call', text: 'doubler'),
          (kind: ElementKind.METHOD, name: 'call', text: 'doubler'),
          (kind: ElementKind.METHOD, name: 'call', text: 'call'),
        ]),
      );
    },
  );

  test(
    'an object pattern uses a getter by its name, or right before the variable of `:name`',
    () {
      return expectLater(
        usesIn(
          '''
class Shape {
  int get sides => 3;
}

void f(Object o) {
  if (o case Shape(sides: 3)) {}
  if (o case Shape(:final sides)) {}
}
''',
          {.GETTER},
        ),
        completion([
          (kind: ElementKind.GETTER, name: 'sides', text: 'sides'),
          (kind: ElementKind.GETTER, name: 'sides', text: ''),
        ]),
      );
    },
  );

  test(
    'a `this.` parameter writes its field, and an argument by its name and a `super.` parameter use the parameter',
    () {
      return expectLater(
        usesIn(
          '''
class Base {
  Base({this.size = 0});
  final int size;
}

class Sub extends Base {
  Sub({super.size});
}

void f() => Base(size: 1);
''',
          {.FIELD, .PARAMETER},
        ),
        completion([
          (kind: ElementKind.FIELD, name: 'size', text: 'size'),
          (kind: ElementKind.PARAMETER, name: 'size', text: 'size'),
          (kind: ElementKind.PARAMETER, name: 'size', text: 'size'),
        ]),
      );
    },
  );

  test(
    'a doc comment link uses what it names, and covers `.name` for a constructor',
    () {
      return expectLater(
        usesIn(
          '''
class Foo {
  Foo();
  Foo.named();
}

/// See [Foo], [Foo.named] and [Foo.new].
void f() {}
''',
          {.CLASS, .CONSTRUCTOR},
        ),
        completion([
          // The class name of a constructor declaration uses the class.
          (kind: ElementKind.CLASS, name: 'Foo', text: 'Foo'),
          (kind: ElementKind.CLASS, name: 'Foo', text: 'Foo'),
          (kind: ElementKind.CLASS, name: 'Foo', text: 'Foo'),
          (kind: ElementKind.CONSTRUCTOR, name: 'named', text: '.named'),
          (kind: ElementKind.CONSTRUCTOR, name: 'new', text: '.new'),
        ]),
      );
    },
  );

  test(
    'an extension override uses its extension, and a combinator uses the declaration that it shows',
    () {
      return expectLater(
        usesIn(
          '''
import 'shown.dart' show shown;

extension Doubled on int {
  int get doubled => this;
}

void f() => Doubled(shown).doubled;
''',
          {.EXTENSION, .GETTER, .TOP_LEVEL_VARIABLE},
        ),
        completion([
          (kind: ElementKind.TOP_LEVEL_VARIABLE, name: 'shown', text: 'shown'),
          (kind: ElementKind.EXTENSION, name: 'Doubled', text: 'Doubled'),
          (kind: ElementKind.GETTER, name: 'shown', text: 'shown'),
          (kind: ElementKind.GETTER, name: 'doubled', text: 'doubled'),
        ]),
      );
    },
  );

  test(
    'a local function is used, but a local variable, a parameter and a type parameter are not',
    () {
      return expectLater(
        usesIn(
          '''
T f<T>(T value) {
  int local = 1;
  int helper() => local;
  return helper() as T;
}
''',
          {.FUNCTION, .LOCAL_VARIABLE, .PARAMETER, .TYPE_PARAMETER},
        ),
        completion([
          (kind: ElementKind.FUNCTION, name: 'helper', text: 'helper'),
        ]),
      );
    },
  );
}
