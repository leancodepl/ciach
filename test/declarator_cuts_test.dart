@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/declarator_cuts.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/removal.dart';

/// Cuts fields and top-level variables out of their statements as the
/// analysis server reads them, then removes them with the remover.
void main() {
  late Directory tempDir;
  late LspClient client;
  var files = 0;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_declarator_cuts_');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Returns [source] after removing the variables named [names] from it, cut
  /// where the syntax nodes say.
  Future<String> remove(String source, List<String> names) async {
    final path = p.join(tempDir.path, 'lib${files++}.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final sources = SourceIndex()..cacheLines(path, source.split('\n'));
    final tokens = await semanticTokensOrEmpty(client, sources, path);
    sources.cacheSemanticTokens(path, tokens);
    final fetch = ReferenceFetch(
      options: FinderOptions(rootPath: tempDir.path),
      sources: sources,
    );
    final removed = [
      for (final name in names)
        (
          path: path,
          name: tokens
              .firstWhere(
                (token) =>
                    token.text == name &&
                    token.modifiers.contains('declaration'),
              )
              .start,
        ),
    ];
    // As the settler does: the removed names first, then the other names in
    // their statements.
    await fetch.fetchSelectionRanges(client, {
      path: {for (final declarator in removed) declarator.name},
    });
    await fetch.fetchSelectionRanges(client, sources.declaratorProbes(removed));
    final cuts = sources.declaratorCuts(removed);
    removeDeclarations([
      for (final declarator in removed)
        decl(
          startLine: declarator.name.line,
          startColumn: declarator.name.character,
          endLine: declarator.name.line,
          endColumn: declarator.name.character + 1,
          kind: .variable,
          cut: cuts[declarator],
          filePath: p.basename(path),
        ),
    ], tempDir.path);
    return File(path).readAsStringSync();
  }

  test('removes the whole statement with its doc comment and annotation '
      'when every declarator goes', () async {
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
  });

  test('takes the comma after a declarator, or before the last one', () async {
    const source = 'var a = 1, b = 2, c = 3;\n';
    expect(await remove(source, ['a']), 'var b = 2, c = 3;\n');
    expect(await remove(source, ['b']), 'var a = 1, c = 3;\n');
    expect(await remove(source, ['c']), 'var a = 1, b = 2;\n');
    expect(await remove(source, ['b', 'c']), 'var a = 1;\n');
  });

  test('keeps a comment between declarators out of the cut shape', () async {
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

  test('a name declared in an initializer is no declarator', () async {
    expect(
      await remove('var a = 1, b = [1].map((x) => x).length;\n', ['a']),
      'var b = [1].map((x) => x).length;\n',
    );
  });
}
