import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// `--remove` deleting the files it leaves empty, and the directives naming
/// them.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_emptied_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('emptied files', () {
    void write(String relativePath, String content) {
      File(p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
    }

    String read(String relativePath) => File(
      p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))),
    ).readAsStringSync();

    bool exists(String relativePath) => File(
      p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))),
    ).existsSync();

    /// `void gone() {}` on line index [line].
    UnusedDeclaration gone(String filePath, {int line = 2}) => .new(
      name: 'gone',
      kind: .function,
      filePath: filePath,
      line: line + 1,
      column: 6,
      isPrivate: false,
      range: (startLine: line, startColumn: 0, endLine: line, endColumn: 14),
    );

    setUp(() {
      write('pubspec.yaml', 'name: pkg\n');
      write('.dart_tool/package_config.json', packageConfig({'pkg': '.'}));
    });

    test('deletes a file left with nothing but imports and drops the '
        'directives naming it — relative, package:, and an export', () {
      write('lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('lib/user.dart', '''
import 'package:pkg/dead.dart';
import 'dart:io';

void kept() {}
''');
      write('lib/sub/relative.dart', '''
import '../dead.dart' show gone;

void alsoKept() {}
''');
      write('lib/barrel.dart', '''
export 'dead.dart';
export 'user.dart';
''');

      final result = removeDeclarations([gone('lib/dead.dart')], tempDir.path);

      expect(exists('lib/dead.dart'), isFalse);
      expect(result.filesChanged, 1);
      final deleted = result.deletedFiles.single;
      expect(deleted.filePath, 'lib/dead.dart');
      expect(deleted.unlinkedFrom, [
        'lib/barrel.dart',
        'lib/sub/relative.dart',
        'lib/user.dart',
      ]);
      expect(read('lib/user.dart'), "import 'dart:io';\n\nvoid kept() {}\n");
      expect(read('lib/sub/relative.dart'), '\nvoid alsoKept() {}\n');
      expect(read('lib/barrel.dart'), "export 'user.dart';\n");
    });

    test('a `library` line and comments do not keep a file', () {
      write('lib/dead.dart', '''
// Copyright: nobody.

/// Docs for the library.
library dead;

// ignore_for_file: unused_import
import 'dart:async';

/// Gone.
void gone() {}
''');
      removeDeclarations([gone('lib/dead.dart', line: 9)], tempDir.path);
      expect(exists('lib/dead.dart'), isFalse);
    });

    test('a file that exports something stays, even once its own last '
        'declaration is gone', () {
      write('lib/dead.dart', '''
export 'other.dart';

void gone() {}
''');
      write('lib/other.dart', 'void other() {}\n');
      final result = removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isTrue);
      expect(read('lib/dead.dart'), "export 'other.dart';\n\n");
      expect(result.deletedFiles, isEmpty);
    });

    test('an export keeps its file whichever directives sit around it', () {
      // Only the export matters, not the import or the `show`.
      write('pubspec.yaml', 'name: pkg\n');
      write('lib/other.dart', 'class Kept {}\n');
      write('lib/dead.dart', '''
import 'dart:async';
export 'package:pkg/other.dart' show Kept;

class DeadClass {}
''');
      final result = removeDeclarations([
        const .new(
          name: 'DeadClass',
          kind: .class$,
          filePath: 'lib/dead.dart',
          line: 4,
          column: 7,
          isPrivate: false,
          range: (startLine: 3, startColumn: 0, endLine: 3, endColumn: 17),
        ),
      ], tempDir.path);

      expect(exists('lib/dead.dart'), isTrue);
      expect(result.deletedFiles, isEmpty);
      expect(
        read('lib/dead.dart'),
        contains("export 'package:pkg/other.dart'"),
      );
      expect(read('lib/dead.dart'), isNot(contains('DeadClass')));
    });

    test('a file that still owns a part stays', () {
      write('lib/dead.dart', '''
part 'dead.g.dart';

void gone() {}
''');
      write('lib/dead.g.dart', "part of 'dead.dart';\n");
      removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isTrue);
      expect(exists('lib/dead.g.dart'), isTrue);
    });

    test('an emptied part file is deleted with its `part` line, and the '
        'owner left with nothing but imports follows it', () {
      write('lib/owner.dart', '''
import 'dart:async';

part 'piece.dart';
''');
      write('lib/piece.dart', '''
part of 'owner.dart';

void gone() {}
''');
      write('bin/main.dart', '''
import 'package:pkg/owner.dart';

void main() {}
''');

      final result = removeDeclarations([gone('lib/piece.dart')], tempDir.path);

      expect(exists('lib/piece.dart'), isFalse);
      expect(exists('lib/owner.dart'), isFalse);
      expect(result.deletedFiles.map((d) => d.filePath), [
        'lib/piece.dart',
        'lib/owner.dart',
      ]);
      expect(read('bin/main.dart'), '\nvoid main() {}\n');
    });

    test('a barrel left with nothing once its only export is deleted '
        'follows it', () {
      write('lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('lib/barrel.dart', "export 'dead.dart';\n");
      write('bin/main.dart', '''
import 'package:pkg/barrel.dart';

void main() {}
''');

      final result = removeDeclarations([gone('lib/dead.dart')], tempDir.path);

      expect(exists('lib/dead.dart'), isFalse);
      expect(exists('lib/barrel.dart'), isFalse);
      expect(result.deletedFiles.map((d) => d.filePath), [
        'lib/dead.dart',
        'lib/barrel.dart',
      ]);
      expect(read('bin/main.dart'), '\nvoid main() {}\n');
    });

    test('a file named in a conditional import stays', () {
      write('lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('lib/switch.dart', '''
import 'stub.dart' if (dart.library.io) 'dead.dart';

void kept() {}
''');
      write('lib/stub.dart', 'void stub() {}\n');
      final result = removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isTrue);
      expect(result.deletedFiles, isEmpty);
      expect(read('lib/switch.dart'), contains("'dead.dart'"));
    });

    test('a `package:` URI of a package no package config lists keeps the '
        'file '
        'when the paths line up', () {
      write('lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('lib/user.dart', '''
import 'package:mystery/dead.dart';

void kept() {}
''');
      removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isTrue);
      expect(read('lib/user.dart'), contains('package:mystery/dead.dart'));
    });

    test('a `package:` URI of another package under the root is not this '
        'file', () {
      write('lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('example/pubspec.yaml', 'name: sample\n');
      write(
        'example/.dart_tool/package_config.json',
        packageConfig({'sample': '.'}),
      );
      write('example/lib/dead.dart', 'void sampleDead() {}\n');
      write('example/bin/main.dart', '''
import 'package:sample/dead.dart';

void main() {}
''');
      removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isFalse);
      expect(
        read('example/bin/main.dart'),
        contains('package:sample/dead.dart'),
      );
    });

    test('a `package:` URI of a path dependency outside the root is not '
        'this file', () {
      write('app/pubspec.yaml', 'name: app\n');
      write(
        'app/.dart_tool/package_config.json',
        packageConfig({'app': '.', 'core': '../core'}),
      );
      write('app/lib/dead.dart', '''
import 'dart:async';

void gone() {}
''');
      write('app/lib/user.dart', '''
import 'package:core/dead.dart';

void kept() {}
''');
      write('core/pubspec.yaml', 'name: core\n');
      write('core/lib/dead.dart', 'void coreDead() {}\n');
      removeDeclarations([gone('lib/dead.dart')], p.join(tempDir.path, 'app'));
      expect(exists('app/lib/dead.dart'), isFalse);
      expect(read('app/lib/user.dart'), contains('package:core/dead.dart'));
    });

    test('a file nothing was removed from is never deleted, even if empty', () {
      write('lib/placeholder.dart', '// Reserved for later.\n');
      write('lib/dead.dart', '''
import 'placeholder.dart';

void gone() {}
''');
      removeDeclarations([gone('lib/dead.dart')], tempDir.path);
      expect(exists('lib/dead.dart'), isFalse);
      expect(exists('lib/placeholder.dart'), isTrue);
    });

    test('a file with a declaration left is not deleted, and its import of '
        'a deleted file is dropped whole even across lines', () {
      write('lib/dead.dart', 'void gone() {}\n');
      write('lib/user.dart', '''
import 'dead.dart'
    show gone,
        other;

/// Still here.
void kept() {}
''');
      removeDeclarations([gone('lib/dead.dart', line: 0)], tempDir.path);
      expect(exists('lib/dead.dart'), isFalse);
      expect(read('lib/user.dart'), '\n/// Still here.\nvoid kept() {}\n');
    });

    test('a report-only finding does not empty its file', () {
      write('lib/dead.dart', 'void gone() {}\n');
      const blocked = UnusedDeclaration(
        name: 'gone',
        kind: .function,
        filePath: 'lib/dead.dart',
        line: 1,
        column: 6,
        isPrivate: false,
        range: (startLine: 0, startColumn: 0, endLine: 0, endColumn: 14),
        removalBlocked: true,
      );
      final result = removeDeclarations([blocked], tempDir.path);
      expect(exists('lib/dead.dart'), isTrue);
      expect(result.filesChanged, 0);
      expect(result.deletedFiles, isEmpty);
    });
  });
}
