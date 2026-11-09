@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/source/declarator_cuts.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/outlines.dart';
import '../support/removal.dart';
import '../support/test_package.dart';

/// Removes fields and top-level variables with cuts worked out from the
/// syntax nodes that the analyzer gives.
void main() {
  late TestPackage package;

  setUpAll(() => package = .new('declarator_cuts'));

  tearDownAll(() => package.dispose());

  /// Writes [source] to a new file, removes the variables named [names] from it
  /// as `--remove` would, and returns the result.
  Future<String> remove(String source, List<String> names) async {
    final path = package.writeNew(source);
    final outline = (await package.files.of(path))!.outline;
    final removed = [
      for (final name in names)
        (
          path: path,
          name: nestedIn(
            outline,
          ).firstWhere((node) => node.element.name == name).nameRange.start,
        ),
    ];
    final cuts = package.files.declaratorCuts(removed);
    removeDeclarations([
      for (final declarator in removed)
        decl(
          startLine: declarator.name.line,
          startColumn: declarator.name.character,
          endLine: declarator.name.line,
          endColumn: declarator.name.character + 1,
          kind: .variable,
          cut: cuts[declarator],
          filePath: p.relative(path, from: package.root),
        ),
    ], package.root);
    return File(path).readAsStringSync();
  }

  test(
    'removes the whole statement with its doc comment and annotation when every declarator goes',
    () async {
      expect(
        await remove(
          '''
class C {
  /// Doc.
  @Deprecated('x')
  int a = 1, /* why */ b = 2;
  int kept = 0;
}
''',
          ['a', 'b'],
        ),
        '''
class C {
  int kept = 0;
}
''',
      );
    },
  );

  test('takes the comma after a declarator, or before the last one', () async {
    const source = 'var a = 1, b = 2, c = 3;\n';
    expect(await remove(source, ['a']), 'var b = 2, c = 3;\n');
    expect(await remove(source, ['b']), 'var a = 1, c = 3;\n');
    expect(await remove(source, ['c']), 'var a = 1, b = 2;\n');
    expect(await remove(source, ['b', 'c']), 'var a = 1;\n');
  });

  test('handles comments between and after variables', () async {
    expect(
      await remove(
        '''
class C {
  int g = 1, // first
      h = 2;
  int i = 1 /* ; */, j = 2;
}
''',
        ['g', 'h', 'i', 'j'],
      ),
      '''
class C {
}
''',
    );
  });

  test('cuts a declarator from a statement split over lines', () async {
    expect(
      await remove(
        '''
class C {
  final int
      e = 1,
      f = 2;
}
''',
        ['f'],
      ),
      '''
class C {
  final int
      e = 1;
}
''',
    );
  });

  test('does not take a closure parameter for a variable', () async {
    expect(
      await remove('var a = 1, b = [1].map((x) => x).length;\n', ['a']),
      'var b = [1].map((x) => x).length;\n',
    );
  });
}
