/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/test_package.dart';

/// The references that `ReferenceIndex` finds, read through `ResolvedFiles`,
/// which feeds it every file that it resolves.
void main() {
  late TestPackage package;

  setUp(() => package = .new('reference_index'));

  tearDown(() => package.dispose());

  /// The references of the declaration whose name is the [occurrence]th
  /// [name] in the file at [path], after every file is resolved.
  Future<List<LocationText>?> referencesTo(
    String path,
    String name, {
    int occurrence = 0,
  }) async {
    await package.files.resolveAll(const []);
    final absolute = p.join(package.root, path);
    return package.files
        .referencesTo(
          absolute,
          positionOfName(absolute, name, occurrence: occurrence),
        )
        ?.map((location) => locationText(location, package.root))
        .toList();
  }

  test(
    'a field is referenced by its reads, its writes and its `this.` parameters, sorted by file and line',
    () async {
      package.writeAll({
        'lib/b.dart': '''
import 'a.dart';

void use(Box box) => box.size = box.size + 1;
''',
        'lib/a.dart': '''
class Box {
  Box({this.size = 0});
  int size;
}

Box make() => Box(size: 2);
''',
      });

      expect(await referencesTo('lib/a.dart', 'size', occurrence: 1), [
        (file: 'lib/a.dart', line: 2, text: 'size'),
        (file: 'lib/a.dart', line: 6, text: 'size'),
        (file: 'lib/b.dart', line: 3, text: 'size'),
        (file: 'lib/b.dart', line: 3, text: 'size'),
      ]);
    },
  );

  test('a getter is referenced by the writes of its setter too', () async {
    package.writeAll({
      'lib/a.dart': '''
class Box {
  int get size => 0;
  set size(int value) {}
}

void use(Box box) => box.size = 1;
''',
    });

    expect(await referencesTo('lib/a.dart', 'size'), [
      (file: 'lib/a.dart', line: 6, text: 'size'),
    ]);
  });

  test(
    'an instance method is referenced through the types above and below its type, but not by a method of the same name in an unrelated type',
    () async {
      package.writeAll({
        'lib/a.dart': '''
abstract class Shape {
  void draw();
}

class Circle extends Shape {
  @override
  void draw() {}
}

class Dot extends Circle {}

class Pen {
  void draw() {}
}

void use(Shape shape, Dot dot, Pen pen) {
  shape.draw();
  dot.draw();
  pen.draw();
}
''',
      });

      expect(await referencesTo('lib/a.dart', 'draw', occurrence: 1), [
        (file: 'lib/a.dart', line: 17, text: 'draw'),
        (file: 'lib/a.dart', line: 18, text: 'draw'),
      ]);
    },
  );

  test(
    'a private member is not referenced by a member of the same name in another library',
    () async {
      package.writeAll({
        'lib/a.dart': '''
class Base {
  void _run() {}
}

void use(Base base) => base._run();
''',
        'lib/b.dart': '''
import 'a.dart';

class Sub extends Base {
  void _run() {}
}

void use(Sub sub) => sub._run();
''',
      });

      expect(await referencesTo('lib/a.dart', '_run'), [
        (file: 'lib/a.dart', line: 5, text: '_run'),
      ]);
    },
  );

  test(
    'a static method is not referenced by a static method of the same name in a subtype',
    () async {
      package.writeAll({
        'lib/a.dart': '''
class Base {
  static void create() {}
}

class Sub extends Base {
  static void create() {}
}

void use() {
  Base.create();
  Sub.create();
}
''',
      });

      expect(await referencesTo('lib/a.dart', 'create'), [
        (file: 'lib/a.dart', line: 10, text: 'create'),
      ]);
    },
  );

  test(
    'a declaration is referenced from another package under the root, which another analysis context resolves',
    () async {
      package.writeCoreAndApp(
        core: 'void shared() {}\n',
        app: '''
import 'package:core/core.dart';

void main() => shared();
''',
      );

      expect(await referencesTo('core/lib/core.dart', 'shared'), [
        (file: 'app/lib/app.dart', line: 3, text: 'shared'),
      ]);
    },
  );

  test('finds nothing where no declaration has its name', () async {
    package.writeAll({'lib/a.dart': 'void f() {}\n'});

    expect(await referencesTo('lib/a.dart', '{}'), isNull);
  });
}
