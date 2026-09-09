import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// `removeDeclarations` on files it leaves with nothing: they are deleted, and
/// the `import`/`export`/`part` directives elsewhere that pointed at them go
/// too, so no directive is left resolving to a file that is gone.
void main() {
  late Directory tempDir;

  File fileAt(String relativePath) =>
      File(p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))));

  void write(String relativePath, String content) {
    fileAt(relativePath)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ciach_deletion_test_');
    // The package name `package:` URIs of its own files start with.
    write('pubspec.yaml', 'name: pkg\nenvironment:\n  sdk: ^3.10.0\n');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String read(String relativePath) => fileAt(relativePath).readAsStringSync();

  bool exists(String relativePath) => fileAt(relativePath).existsSync();

  /// A whole-node finding covering exactly [snippet] in [relativePath].
  UnusedDeclaration declarationOf(
    String relativePath,
    String snippet, {
    SymbolKind kind = .function,
  }) {
    final content = read(relativePath);
    final start = content.indexOf(snippet);
    expect(start, isNonNegative, reason: '$snippet not in $relativePath');
    final end = start + snippet.length;
    (int, int) position(int offset) {
      final before = content.substring(0, offset);
      final line = '\n'.allMatches(before).length;
      return (line, offset - (before.lastIndexOf('\n') + 1));
    }

    final (startLine, startColumn) = position(start);
    final (endLine, endColumn) = position(end);
    return UnusedDeclaration(
      name: 'x',
      kind: kind,
      filePath: relativePath,
      line: startLine + 1,
      column: startColumn + 1,
      isPrivate: false,
      range: (
        startLine: startLine,
        startColumn: startColumn,
        endLine: endLine,
        endColumn: endColumn,
      ),
    );
  }

  test('deletes a file left with only comments and imports, and drops every '
      'directive elsewhere that pointed at it', () {
    write('lib/dead.dart', '''
// Copyright header.

import 'dart:async';

/// Doc.
void dead() {}
''');
    write('lib/user.dart', '''
import 'package:pkg/dead.dart';
import 'dead.dart' as d;

void keep() {}
''');
    write('test/user_test.dart', '''
import 'package:pkg/dead.dart' show dead;

void main() {}
''');
    // Another package's `dead.dart`: same basename, not this file.
    write('lib/other.dart', '''
import 'package:other/dead.dart';

void keep() {}
''');

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(exists('lib/dead.dart'), isFalse);
    expect(result.filesChanged, 1);
    expect(result.deletedFiles, ['lib/dead.dart']);
    expect(
      result.removedDirectives,
      unorderedEquals([
        (
          filePath: 'lib/user.dart',
          directive: "import 'package:pkg/dead.dart';",
        ),
        (filePath: 'lib/user.dart', directive: "import 'dead.dart' as d;"),
        (
          filePath: 'test/user_test.dart',
          directive: "import 'package:pkg/dead.dart' show dead;",
        ),
      ]),
    );
    expect(read('lib/user.dart').trim(), 'void keep() {}');
    expect(read('test/user_test.dart').trim(), 'void main() {}');
    expect(
      read('lib/other.dart'),
      contains("import 'package:other/dead.dart';"),
    );
  });

  test('a file that still exports, or still has parts, is kept', () {
    write('lib/barrel.dart', "export 'kept.dart';\n\nclass Dead {}\n");
    write('lib/kept.dart', 'class Kept {}\n');
    write('lib/lib.dart', "part 'part.dart';\n\nclass Dead2 {}\n");
    write('lib/part.dart', "part of 'lib.dart';\n\nclass Live {}\n");

    final result = removeDeclarations([
      declarationOf('lib/barrel.dart', 'class Dead {}', kind: .class$),
      declarationOf('lib/lib.dart', 'class Dead2 {}', kind: .class$),
    ], tempDir.path);

    expect(result.filesChanged, 2);
    expect(result.deletedFiles, isEmpty);
    expect(result.removedDirectives, isEmpty);
    expect(read('lib/barrel.dart').trim(), "export 'kept.dart';");
    expect(read('lib/lib.dart').trim(), "part 'part.dart';");
  });

  test('a barrel emptied by dropping its exports is deleted in turn, and its '
      'importers are fixed', () {
    write('lib/dead.dart', 'void dead() {}\n');
    write('lib/barrel.dart', "export 'dead.dart';\n");
    write(
      'lib/app.dart',
      "import 'package:pkg/barrel.dart';\n\nvoid main() {}\n",
    );

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.deletedFiles, ['lib/barrel.dart', 'lib/dead.dart']);
    expect(exists('lib/barrel.dart'), isFalse);
    expect(read('lib/app.dart').trim(), 'void main() {}');
    expect(result.removedDirectives, [
      (filePath: 'lib/barrel.dart', directive: "export 'dead.dart';"),
      (
        filePath: 'lib/app.dart',
        directive: "import 'package:pkg/barrel.dart';",
      ),
    ]);
  });

  test('a part file left with only `part of` is deleted and its `part` '
      'directive dropped from the library', () {
    write(
      'lib/lib.dart',
      "library pkg;\n\npart 'part.dart';\n\nvoid keep() {}\n",
    );
    write('lib/part.dart', "part of 'lib.dart';\n\nvoid dead() {}\n");

    final result = removeDeclarations([
      declarationOf('lib/part.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.deletedFiles, ['lib/part.dart']);
    expect(exists('lib/part.dart'), isFalse);
    final lib = read('lib/lib.dart');
    expect(lib, isNot(contains("part 'part.dart';")));
    expect(lib, contains('library pkg;'));
    expect(lib, contains('void keep() {}'));
  });

  test('an annotated `library` directive counts as nothing', () {
    write(
      'lib/dead.dart',
      "@Deprecated('old')\nlibrary;\n\n/// Doc.\nvoid dead() {}\n",
    );

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.deletedFiles, ['lib/dead.dart']);
  });

  test('a conditional import of a deleted file is dropped whole', () {
    write('lib/dead.dart', 'void dead() {}\n');
    write('lib/dead_io.dart', 'void deadIo() {}\n');
    write('lib/cond.dart', '''
import 'dead.dart'
    if (dart.library.io) 'dead_io.dart';

void keep() {}
''');

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.removedDirectives, [
      (
        filePath: 'lib/cond.dart',
        directive: "import 'dead.dart' if (dart.library.io) 'dead_io.dart';",
      ),
    ]);
    expect(read('lib/cond.dart').trim(), 'void keep() {}');
  });

  test('a generated file importing the deleted file is fixed too', () {
    write('lib/dead.dart', 'class Dead {}\n');
    write('lib/dead.mocks.dart', '''
// Mocks generated by Mockito.
import 'package:pkg/dead.dart' as _i1;

class MockDead {}
''');

    removeDeclarations([
      declarationOf('lib/dead.dart', 'class Dead {}', kind: .class$),
    ], tempDir.path);

    final mocks = read('lib/dead.mocks.dart');
    expect(mocks, isNot(contains('import')));
    expect(mocks, contains('class MockDead {}'));
  });

  test('a directive keyword used as an identifier, or a basename in a string, '
      'is left alone', () {
    write('lib/dead.dart', 'void dead() {}\n');
    const tricky = "final part = 'dead.dart';\nconst note = 'see dead.dart';\n";
    write('lib/tricky.dart', tricky);

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.deletedFiles, ['lib/dead.dart']);
    expect(result.removedDirectives, isEmpty);
    expect(read('lib/tricky.dart'), tricky);
  });

  test('a file the removal did not touch is never deleted, whatever it '
      'holds', () {
    write('lib/dead.dart', 'void dead() {}\n');
    const importsOnly = "import 'dart:async';\n";
    write('lib/imports_only.dart', importsOnly);

    final result = removeDeclarations([
      declarationOf('lib/dead.dart', 'void dead() {}'),
    ], tempDir.path);

    expect(result.deletedFiles, ['lib/dead.dart']);
    expect(read('lib/imports_only.dart'), importsOnly);
  });

  test('an emptied extension is deleted whole when reported with its '
      'members', () {
    const source = '''
/// All dead.
extension DeadExtras on int {
  /// Dead.
  int tripled() => this * 3;
}

extension Live on int {
  int doubled() => this * 2;
}

int use() => 2.doubled();
''';
    write('lib/ext.dart', source);

    final result = removeDeclarations([
      declarationOf(
        'lib/ext.dart',
        'extension DeadExtras on int {\n  /// Dead.\n  int tripled() => this * 3;\n}',
        kind: .namespace,
      ),
      declarationOf(
        'lib/ext.dart',
        'int tripled() => this * 3;',
        kind: .method,
      ),
    ], tempDir.path);

    expect(result.deletedFiles, isEmpty);
    final ext = read('lib/ext.dart');
    expect(ext, isNot(contains('DeadExtras')));
    expect(ext, isNot(contains('All dead')));
    expect(ext, contains('extension Live on int {'));
    expect(ext, contains('int use() => 2.doubled();'));
  });
}
