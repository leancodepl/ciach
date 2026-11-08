/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/locations.dart';
import '../support/package_config.dart';
import '../support/resolved_files.dart';

/// The overrides that `TypeHierarchy` finds, read through `ResolvedFiles`,
/// which feeds it every file that it resolves.
void main() {
  late Directory tempDir;

  setUp(() => tempDir = .systemTemp.createTempSync('ciach_type_hierarchy_'));

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Writes the [files] of a package named `app`, by their paths relative to
  /// the package root.
  void writePackage(Map<String, String> files) =>
      writeAppPackage(tempDir.path, files);

  /// The overrides of the member whose name is the [occurrence]th [name] in
  /// the file at [path], after every file is resolved.
  Future<List<LocationText>> overridesOf(
    String path,
    String name, {
    int occurrence = 0,
  }) async {
    final files = resolvedFilesUnder(tempDir.path);
    addTearDown(files.dispose);
    await files.resolveAll(const []);
    final absolute = p.join(tempDir.path, path);
    return files
        .overridesOf(
          absolute,
          positionOfName(absolute, name, occurrence: occurrence),
        )
        .map((location) => locationText(location, tempDir.path))
        .toList();
  }

  test(
    'a method is overridden in its subclasses, also past a class that does not override it, and in its implementations, mixins and enums, sorted by file and line',
    () async {
      writePackage({
        'lib/b.dart': '''
import 'a.dart';

class Other implements Shape {
  @override
  void draw() {}
}
''',
        'lib/a.dart': '''
class Shape {
  void draw() {}
}

class Plain extends Shape {}

class Circle extends Plain {
  @override
  void draw() {}
}

mixin Drawn on Shape {
  @override
  void draw() {}
}

enum Kind implements Shape {
  dot;

  @override
  void draw() {}
}

class Pen {
  void draw() {}
}
''',
      });

      expect(await overridesOf('lib/a.dart', 'draw'), [
        (file: 'lib/a.dart', line: 9, text: 'draw'),
        (file: 'lib/a.dart', line: 14, text: 'draw'),
        (file: 'lib/a.dart', line: 21, text: 'draw'),
        (file: 'lib/b.dart', line: 5, text: 'draw'),
      ]);
    },
  );

  test(
    'a method is overridden by the member of a mixin that a subclass applies',
    () async {
      writePackage({
        'lib/a.dart': '''
class Shape {
  void draw() {}
}

mixin Drawn {
  void draw() {}
}

class Circle extends Shape with Drawn {}
''',
      });

      expect(await overridesOf('lib/a.dart', 'draw'), [
        (file: 'lib/a.dart', line: 6, text: 'draw'),
      ]);
    },
  );

  test(
    'the member of a mixin is not overridden by itself in a class that applies the mixin',
    () async {
      writePackage({
        'lib/a.dart': '''
mixin Drawn {
  void draw() {}
}

class Circle with Drawn {}
''',
      });

      expect(await overridesOf('lib/a.dart', 'draw'), isEmpty);
    },
  );

  test(
    'the field of a mixin is not overridden by itself in a class that applies the mixin',
    () async {
      writePackage({
        'lib/a.dart': '''
mixin Sized {
  int size = 0;
}

class Box with Sized {}
''',
      });

      expect(await overridesOf('lib/a.dart', 'size'), isEmpty);
    },
  );

  test(
    'a field is overridden by a field, and by a setter when it is not final',
    () async {
      writePackage({
        'lib/a.dart': '''
class Box {
  int size = 0;
}

class Big extends Box {
  @override
  int size = 1;
}

class Small extends Box {
  @override
  set size(int value) {}
}
''',
      });

      expect(await overridesOf('lib/a.dart', 'size'), [
        (file: 'lib/a.dart', line: 7, text: 'size'),
        (file: 'lib/a.dart', line: 12, text: 'size'),
      ]);
    },
  );

  test(
    'a final field is overridden by a getter, but not by a setter',
    () async {
      writePackage({
        'lib/a.dart': '''
class Box {
  final int size = 0;
}

class Big extends Box {
  @override
  int get size => 1;
}

class Small extends Box {
  set size(int value) {}
}
''',
      });

      expect(await overridesOf('lib/a.dart', 'size'), [
        (file: 'lib/a.dart', line: 7, text: 'size'),
      ]);
    },
  );

  test('a getter is overridden by getters, not by setters', () async {
    writePackage({
      'lib/a.dart': '''
class Box {
  int get size => 0;
  set size(int value) {}
}

class Big extends Box {
  @override
  int get size => 1;
}

class Small extends Box {
  @override
  set size(int value) {}
}
''',
    });

    expect(await overridesOf('lib/a.dart', 'size'), [
      (file: 'lib/a.dart', line: 8, text: 'size'),
    ]);
  });

  test(
    'a private member is not overridden by a member of the same name in another library',
    () async {
      writePackage({
        'lib/a.dart': '''
class Base {
  void _run() {}
}
''',
        'lib/b.dart': '''
import 'a.dart';

class Sub extends Base {
  void _run() {}
}
''',
      });

      expect(await overridesOf('lib/a.dart', '_run'), isEmpty);
    },
  );

  test(
    'a static method is not overridden by a method of the same name in a subclass',
    () async {
      writePackage({
        'lib/a.dart': '''
class Base {
  static void create() {}
}

class Sub extends Base {
  void create() {}
}
''',
      });

      expect(await overridesOf('lib/a.dart', 'create'), isEmpty);
    },
  );

  test(
    'a member of an extension type is not overridden by the member that an extension type that implements it redeclares',
    () async {
      writePackage({
        'lib/a.dart': '''
extension type Id(int value) {
  int get next => value + 1;
}

extension type UserId(int value) implements Id {
  int get next => value + 2;
}
''',
      });

      expect(await overridesOf('lib/a.dart', 'next'), isEmpty);
    },
  );

  test(
    'a member is overridden in another package under the root, which another analysis context resolves',
    () async {
      File(p.join(tempDir.path, 'core', '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(packageConfig({'core': '.'}));
      File(
        p.join(tempDir.path, 'core', 'pubspec.yaml'),
      ).writeAsStringSync('name: core\n');
      File(p.join(tempDir.path, 'core', 'lib', 'core.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
class Shape {
  void draw() {}
}
''');
      File(p.join(tempDir.path, 'app', '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(packageConfig({'app': '.', 'core': '../core'}));
      File(
        p.join(tempDir.path, 'app', 'pubspec.yaml'),
      ).writeAsStringSync('name: app\n');
      File(p.join(tempDir.path, 'app', 'lib', 'app.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('''
import 'package:core/core.dart';

class Circle extends Shape {
  @override
  void draw() {}
}
''');

      expect(await overridesOf('core/lib/core.dart', 'draw'), [
        (file: 'app/lib/app.dart', line: 5, text: 'draw'),
      ]);
    },
  );

  test('finds nothing where no member has its name', () async {
    writePackage({'lib/a.dart': 'class A {}\n'});

    expect(await overridesOf('lib/a.dart', '{}'), isEmpty);
  });
}
