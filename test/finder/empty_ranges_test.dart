@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/remove/remover.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

/// Pairs of range comments with nothing between them: found by the finder in
/// every scanned file, removed by `--remove` even where no code goes.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  String read(String path) => File(p.join(root.path, path)).readAsStringSync();

  Future<FinderResult> run() =>
      Ciach(.new(rootPath: root.path, exportedPackages: const [])).run();

  setUp(() {
    root = .systemTemp.createTempSync('ciach_empty_ranges_');
    write('pubspec.yaml', '''
name: pkg
environment:
  sdk: ^3.10.0
''');
    write('.dart_tool/package_config.json', packageConfig({'pkg': '.'}));
    write('lib/main.dart', '''
import 'other.dart';

void main() {
  other();
  kept();
}
''');
    write('lib/other.dart', '''
void other() {}

// coverage:ignore-start
// coverage:ignore-end

// dart format off
void kept() {}
// dart format on
''');
    write('lib/blank.dart', '''
// cspell:disable
// cspell:enable
''');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('lists the empty ranges, but not those of an empty file', () async {
    final result = await run();
    expect(result.emptyRanges, [
      (
        filePath: 'lib/other.dart',
        line: 3,
        open: 'coverage:ignore-start',
        close: 'coverage:ignore-end',
      ),
    ]);
    expect(result.emptyFiles, ['lib/blank.dart']);
  });

  test('removal takes them out of a file with no code to remove', () async {
    final result = await run();
    final removal = removeDeclarations(
      result.unused,
      root.path,
      emptyRanges: result.emptyRanges,
    );
    expect(removal.removedRanges, 1);
    expect(read('lib/other.dart'), '''
void other() {}


// dart format off
void kept() {}
// dart format on
''');
  });
}
