/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/source/locations.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';
import '../support/resolved_files.dart';

/// A reference as the tests compare it: the file, relative to the package
/// root, the one-based line, and the text that it covers.
typedef _Reference = ({String file, int line, String text});

/// The references that `ReferenceIndex` finds, read through `ResolvedFiles`,
/// which feeds it every file that it resolves.
void main() {
  late Directory tempDir;

  setUp(() => tempDir = .systemTemp.createTempSync('ciach_reference_index_'));

  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Writes the [files] of a package named `app`, by their paths relative to
  /// the package root.
  void writePackage(Map<String, String> files, {String root = '.'}) {
    for (final MapEntry(key: path, value: source) in {
      '.dart_tool/package_config.json': packageConfig({'app': '.'}),
      ...files,
    }.entries) {
      File(p.join(tempDir.path, root, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(source);
    }
  }

  /// [location] as the tests compare it.
  _Reference referenceIn(Location location) {
    final path = Uri.parse(location.uri).toFilePath();
    final line = File(path).readAsLinesSync()[location.range.start.line];
    return (
      file: p.relative(path, from: tempDir.path),
      line: location.range.start.line + 1,
      text: line.substring(
        location.range.start.character,
        location.range.end.character,
      ),
    );
  }

  /// The references of the declaration whose name is the [occurrence]th
  /// [name] in the file at [path], after every file is resolved.
  Future<List<_Reference>?> referencesTo(
    String path,
    String name, {
    int occurrence = 0,
  }) async {
    final files = resolvedFilesUnder(tempDir.path);
    addTearDown(files.dispose);
    await files.resolveAll(const []);
    final absolute = p.join(tempDir.path, path);
    final source = File(absolute).readAsStringSync();
    var offset = source.indexOf(name);
    for (var i = 0; i < occurrence; i++) {
      offset = source.indexOf(name, offset + 1);
    }
    return files
        .referencesTo(absolute, _positionAt(source, offset))
        ?.map(referenceIn)
        .toList();
  }

  test(
    'a field is referenced by its reads, its writes and its `this.` parameters, sorted by file and line',
    () async {
      writePackage({
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
    writePackage({
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
      writePackage({
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
      writePackage({
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
      writePackage({
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
      File(p.join(tempDir.path, 'core', '.dart_tool', 'package_config.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync(packageConfig({'core': '.'}));
      File(
        p.join(tempDir.path, 'core', 'pubspec.yaml'),
      ).writeAsStringSync('name: core\n');
      File(p.join(tempDir.path, 'core', 'lib', 'core.dart'))
        ..createSync(recursive: true)
        ..writeAsStringSync('void shared() {}\n');
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

void main() => shared();
''');

      expect(await referencesTo('core/lib/core.dart', 'shared'), [
        (file: 'app/lib/app.dart', line: 3, text: 'shared'),
      ]);
    },
  );

  test('finds nothing where no declaration has its name', () async {
    writePackage({'lib/a.dart': 'void f() {}\n'});

    expect(await referencesTo('lib/a.dart', '{}'), isNull);
  });
}

/// The position of [offset] in [source].
Position _positionAt(String source, int offset) {
  final before = source.substring(0, offset);
  final line = '\n'.allMatches(before).length;
  return .new(line: line, character: offset - (before.lastIndexOf('\n') + 1));
}
