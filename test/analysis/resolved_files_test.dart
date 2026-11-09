/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/source/locations.dart';
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/previews_package.dart';
import '../support/test_package.dart';

void main() {
  late TestPackage package;

  setUpAll(() => package = previewsPackage());

  tearDownAll(() => package.dispose());

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

  test(
    'resolves the supertypes of each class and mixin, and of nothing else',
    () async {
      final file = await package.resolveNew('''
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
          for (final declaration in file.outline.children)
            declaration.element.name:
                file.supertypes[declaration.nameRange.start],
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
      final file = await package.resolveNew(source);

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
      final file = await package.resolveNew('''
class Base {}

class Derived extends Base {}
''', dir: 'test');

      expect(file.supertypes.values.last, {app('Base'), object});
    },
  );

  test(
    'gives the first compile error of a file, and none for a file without one',
    () async {
      final broken = await package.resolveNew('''
void a() {}

void b() => missing();

void c() => alsoMissing();
''');
      final valid = await package.resolveNew('void a() {}\n');

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
