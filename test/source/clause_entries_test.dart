@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/clause_entries.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Range;
import 'package:test/test.dart';

import '../support/removal.dart';

/// Cuts entries from `with` and `implements` clauses as the analysis server
/// reads them: its tokens, syntax nodes and outline.
void main() {
  late Directory tempDir;
  late LspClient client;
  var files = 0;

  setUpAll(() async {
    tempDir = .systemTemp.createTempSync('ciach_clauses_');
    client = await LspClient.start();
    await client.initialize(tempDir.uri);
    await client.waitForAnalysisComplete();
  });

  tearDownAll(() async {
    await client.dispose();
    tempDir.deleteSync(recursive: true);
  });

  /// Writes [source] to a new file and caches its semantic tokens.
  Future<(String, SourceIndex, ReferenceFetch)> index(String source) async {
    final path = p.join(tempDir.path, 'lib${files++}.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final sources = SourceIndex()..cacheLines(path, source.split('\n'));
    sources.cacheSemanticTokens(
      path,
      await semanticTokensOrEmpty(client, sources, path),
    );
    return (
      path,
      sources,
      ReferenceFetch(
        options: .new(rootPath: tempDir.path),
        sources: sources,
      ),
    );
  }

  /// Returns the clause entries for [names], searched for in [source] after the
  /// text [clause], as `clauseEntryAt` reads them once the selection ranges at
  /// the names are fetched.
  Future<(String, SourceIndex, ReferenceFetch, List<ClauseEntry?>)> entriesIn(
    String source,
    String clause,
    List<String> names,
  ) async {
    final (path, sources, fetch) = await index(source);
    final unit = await client.outline(File(path).uri);
    final clauseStart = source.indexOf(clause);
    int nameAt(String name) {
      final start = source.indexOf(RegExp('\\b$name\\b'), clauseStart);
      expect(start, isNot(-1), reason: '$name after $clause');
      return start;
    }

    final ranges = [
      for (final name in names)
        Range(
          start: sources.positionOf(path, nameAt(name)),
          end: sources.positionOf(path, nameAt(name) + name.length),
        ),
    ];
    await fetch.fetchSelectionRanges(client, {
      path: {for (final range in ranges) range.start},
    });
    return (
      path,
      sources,
      fetch,
      [
        for (final (i, range) in ranges.indexed)
          sources.clauseEntryAt(
            .new(uri: File(path).uri.toString(), range: range),
            names[i],
            unit,
          ),
      ],
    );
  }

  /// Returns [source] after removing the [cut] names from the clause that
  /// starts with [clause], fetching selection ranges as the settler does.
  Future<String> cutFrom(String source, String clause, List<String> cut) async {
    final (path, sources, fetch, entries) = await entriesIn(
      source,
      clause,
      cut,
    );
    expect(entries, everyElement(isNotNull));
    await fetch.fetchSelectionRanges(client, {
      path: {
        for (final entry in entries.nonNulls)
          ...sources.namesInClause(path, entry.clause),
      },
    });
    final removals = sources.clauseCuts(entries.nonNulls, tempDir.path).values;
    removeDeclarations([
      for (final removal in removals.toSet())
        decl(
          startLine: removal.range.startLine,
          startColumn: removal.range.startColumn,
          endLine: removal.range.endLine,
          endColumn: removal.range.endColumn,
          kind: removal.kind,
          cut: removal.cut,
          filePath: removal.filePath,
        ),
    ], tempDir.path);
    return File(path).readAsStringSync();
  }

  const types = '''
class B {}
mixin C {}
mixin D {}
mixin E {}
''';

  test('keeps a line comment out of the code when the clause goes', () async {
    expect(
      await cutFrom(
        '${types}class A extends B // note\n    with C {}\n',
        'with C',
        ['C'],
      ),
      '${types}class A extends B // note\n {}\n',
    );
  });

  test('removes the only entry together with the keyword', () async {
    expect(
      await cutFrom('${types}class A extends B with C {}\n', 'with C', ['C']),
      '${types}class A extends B {}\n',
    );
  });

  test('removes entries together with the comma after them', () async {
    expect(
      await cutFrom('${types}class A with C, D, E {}\n', 'with C', ['C', 'D']),
      '${types}class A with E {}\n',
    );
  });

  test(
    'removes entries at the end together with the comma before them',
    () async {
      expect(
        await cutFrom(
          '${types}abstract class A implements Comparable<A>, C, D {}\n',
          'implements',
          ['C', 'D'],
        ),
        '${types}abstract class A implements Comparable<A> {}\n',
      );
    },
  );

  test('removes the whole clause when every entry goes', () async {
    expect(
      await cutFrom('${types}class A with C, D implements E {}\n', 'with C', [
        'C',
        'D',
      ]),
      '${types}class A implements E {}\n',
    );
  });

  test('keeps at least one mixin of a mixin application class', () async {
    expect(
      await cutFrom('${types}class A = B with C, D;\n', 'with C', ['C']),
      '${types}class A = B with D;\n',
    );
    expect(
      await cutFrom('${types}class A = B with C, D;\n', 'with C', ['C', 'D']),
      '${types}class A = B with C, D;\n',
    );
  });

  test('removes entries separated by a comment and line breaks', () async {
    expect(
      await cutFrom(
        '''
${types}abstract class A
    implements
        C, // the first
        D,
        E {}
''',
        'implements',
        ['C', 'E'],
      ),
      '''
${types}abstract class A
    implements
        D {}
''',
    );
  });

  test(
    'reads from the outline whether a clause belongs to a mixin application class',
    () async {
      const source =
          '''
${types}class A = B with C;
class F extends B with C {}
''';
      final (_, _, _, aliased) = await entriesIn(source, 'with C;', ['C']);
      final (_, _, _, extended) = await entriesIn(source, 'with C {', ['C']);

      expect(aliased.single?.keepsOne, isTrue);
      expect(extended.single?.keepsOne, isFalse);
    },
  );

  test('removes a generic entry together with its type arguments', () async {
    expect(
      await cutFrom(
        '${types}mixin G<T> {}\nclass A with C, G<List<int>> {}\n',
        'with C',
        ['G'],
      ),
      '${types}mixin G<T> {}\nclass A with C {}\n',
    );
  });

  test('returns no entry for a type argument of a clause entry', () async {
    final (_, _, _, entries) = await entriesIn(
      '${types}abstract class A implements Comparable<C> {}\n',
      'implements',
      ['C'],
    );

    expect(entries.single, isNull);
  });

  test(
    'returns no entry for a type named outside a with or implements clause',
    () async {
      final (_, _, _, entries) = await entriesIn(
        '${types}class A extends B {}\n',
        'extends',
        ['B'],
      );

      expect(entries.single, isNull);
    },
  );
}
