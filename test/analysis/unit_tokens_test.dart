/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';
import '../support/resolved_files.dart';

/// The tokens that `unitTokens` builds, read through `ResolvedFiles`, which
/// resolves the file first.
void main() {
  late Directory tempDir;
  late ResolvedFiles files;
  var written = 0;

  setUpAll(() {
    tempDir = .systemTemp.createTempSync('ciach_unit_tokens_');
    File(p.join(tempDir.path, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'app': '.'}));
    files = resolvedFilesUnder(tempDir.path);
  });

  tearDownAll(() async {
    await files.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [source] to a new file and returns its tokens.
  Future<List<SemanticToken>> tokensOf(String source) async {
    final path = p.join(tempDir.path, 'lib', 'file${written++}.dart');
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
    return (await files.of(path))!.tokens;
  }

  test(
    'a doc comment is split around the names that it links to, and a line comment is no doc comment',
    () async {
      final tokens = await tokensOf('''
/// See [Foo].
// Not a doc comment.
class Foo {}
''');

      expect(
        [for (final t in tokens.take(4)) (t.text, t.type, t.isDocComment)],
        [
          ('/// See [', 'comment', true),
          ('Foo', 'class', false),
          ('].', 'comment', true),
          ('// Not a doc comment.', 'comment', false),
        ],
      );
    },
  );

  test(
    'an annotation is its `@`, its name, which the `annotation` modifier marks, and its parentheses',
    () async {
      final tokens = await tokensOf('''
@pragma('vm:entry-point')
@override
void f() {}
''');

      expect(
        [
          for (final t in tokens.take(7))
            (t.text, t.type, t.modifiers.contains('annotation')),
        ],
        [
          ('@', 'annotation', false),
          ('pragma', 'class', true),
          ('(', 'annotation', false),
          ("'vm:entry-point'", 'string', false),
          (')', 'annotation', false),
          ('@', 'annotation', false),
          ('override', 'property', true),
        ],
      );
    },
  );

  test(
    'a keyword used as a name is a name, and the names of declarations are marked as declared',
    () async {
      final tokens = await tokensOf('''
void f({required int required}) {}
''');

      expect(
        [for (final t in tokens) (t.text, t.type, t.isDeclaration)],
        [
          ('void', 'keyword', false),
          ('f', 'function', true),
          ('required', 'keyword', false),
          ('int', 'class', false),
          ('required', 'parameter', true),
        ],
      );
    },
  );

  test('every variable of one statement is declared', () async {
    final tokens = await tokensOf('int a = 1, b = 2;\n');

    expect(
      [for (final t in tokens) (t.text, t.isDeclaration)],
      [('int', false), ('a', true), ('1', false), ('b', true), ('2', false)],
    );
  });

  test('`part of` is one keyword', () async {
    final tokens = await tokensOf("part of 'file100.dart';\n");

    expect(tokens.first.text, 'part of');
  });

  test(
    '`sync*` is one keyword, and an import prefix is not declared',
    () async {
      final tokens = await tokensOf('''
import 'dart:math' as math;

Iterable<int> f() sync* {}
''');

      expect(
        [
          for (final t in tokens)
            if (t.text case 'math' || 'sync*') (t.text, t.isDeclaration),
        ],
        [('math', false), ('sync*', false)],
      );
    },
  );

  test(
    'a comment that spans lines has a token on its last line only, as ciach read them from the server',
    () async {
      final tokens = await tokensOf('''
/* first
   last */
void f() {}
''');

      expect(
        [for (final t in tokens.take(2)) (t.line, t.text)],
        [(1, '   last */'), (2, 'void')],
      );
    },
  );

  test('the field names of a record type have no tokens', () async {
    final tokens = await tokensOf('(int x, {int y})? r;\n');

    expect(tokens.map((t) => t.text), ['int', 'int', 'r']);
  });
}
