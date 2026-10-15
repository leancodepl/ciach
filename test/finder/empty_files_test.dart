@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/remove/remover.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

/// Files with nothing but directives and comments before any removal: found
/// by the finder, deleted by `--remove`.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  String read(String path) => File(p.join(root.path, path)).readAsStringSync();

  bool exists(String path) => File(p.join(root.path, path)).existsSync();

  Future<FinderResult> run({bool leaveOutApi = false}) => Ciach(
    .new(
      rootPath: root.path,
      exportedPackages: leaveOutApi ? const ['**'] : const [],
    ),
  ).run();

  setUp(() {
    root = .systemTemp.createTempSync('ciach_empty_files_');
    write('pubspec.yaml', '''
name: pkg
environment:
  sdk: ^3.10.0
''');
    write('.dart_tool/package_config.json', packageConfig({'pkg': '.'}));
    write('lib/blank.dart', '''
// Everything that was here moved to user.dart.
library;

import 'dart:async';
''');
    write('lib/zero.dart', '');
    write('lib/owner.dart', '''
part 'hollow_part.dart';

void owned() {}
''');
    write('lib/hollow_part.dart', "part of 'owner.dart';\n");
    write('lib/io.dart', 'void platform() {}\n');
    write('lib/web.dart', '// Nothing to do on the web.\n');
    write('lib/user.dart', '''
import 'blank.dart';
import 'io.dart' if (dart.library.js_interop) 'web.dart';

void use() => platform();
''');
    write('lib/barrel.dart', "export 'user.dart';\n");
    write('tool/scratch.dart', '/* TODO */\n');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('lists the files with nothing but directives and comments', () async {
    final result = await run();
    expect(result.emptyFiles, [
      'lib/blank.dart',
      'lib/hollow_part.dart',
      'lib/zero.dart',
      'tool/scratch.dart',
    ]);
    expect(result.emptyVariants, ['lib/web.dart']);
  });

  test(
    'a file other packages can import is left out when its package is exported',
    () async {
      final result = await run(leaveOutApi: true);
      expect(result.emptyFiles, ['tool/scratch.dart']);
      expect(result.emptyVariants, isEmpty);
    },
  );

  test('removal deletes them and drops the directives naming them', () async {
    final result = await run();
    final removal = removeDeclarations(
      const [],
      root.path,
      emptyFiles: result.emptyFiles,
    );

    expect(removal.filesChanged, 0);
    expect(removal.deletedFiles.map((d) => d.filePath), result.emptyFiles);
    for (final path in result.emptyFiles) {
      expect(exists(path), isFalse, reason: path);
    }
    expect(read('lib/owner.dart'), '\nvoid owned() {}\n');
    expect(read('lib/user.dart'), '''
import 'io.dart' if (dart.library.js_interop) 'web.dart';

void use() => platform();
''');
    expect(exists('lib/web.dart'), isTrue);
    final again = await run();
    expect(again.emptyFiles, isEmpty);
    expect(again.emptyVariants, ['lib/web.dart']);
  });
}
