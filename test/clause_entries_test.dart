@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/clause_entries.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/remover.dart';
import 'package:ciach/src/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;
import 'package:test/test.dart';

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

  /// [source] written to a new file and indexed from the server.
  Future<(String, SourceIndex)> index(String source) async {
    final path = p.join(tempDir.path, 'lib${files++}.dart');
    File(path).writeAsStringSync(source);
    client.didOpen(File(path).uri, source);
    final sources = SourceIndex()..cacheLines(path, source.split('\n'));
    final tokens = await client.semanticTokens(
      File(path).uri,
      sources.lines(path),
    );
    sources.cacheSemanticTokens(path, tokens);
    final positions = [for (final token in tokens) token.start];
    final ranges = await client.selectionRanges(File(path).uri, positions);
    for (final (i, position) in positions.indexed) {
      if (ranges[i] case final range?) {
        sources.cacheSelectionRange(path, position, range);
      }
    }
    return (path, sources);
  }

  /// The entries of [names] in the clause that follows [clause] in [source],
  /// as `clauseEntryAt` reads them.
  Future<(String, SourceIndex, List<ClauseEntry?>)> entriesIn(
    String source,
    String clause,
    List<String> names,
  ) async {
    final (path, sources) = await index(source);
    final unit = await client.outline(File(path).uri);
    final clauseStart = source.indexOf(clause);
    final starts = sources.lineStarts(path);
    Position at(int offset) {
      final line = starts.lastIndexWhere((start) => start <= offset);
      return .new(line: line, character: offset - starts[line]);
    }

    return (
      path,
      sources,
      [
        for (final name in names)
          if (source.indexOf(RegExp('\\b$name\\b'), clauseStart)
              case final start)
            sources.clauseEntryAt(
              Location(
                uri: File(path).uri.toString(),
                range: Range(start: at(start), end: at(start + name.length)),
              ),
              name,
              unit,
            ),
      ],
    );
  }

  /// Returns [source] after removing the [cut] names from the clause that
  /// starts with [clause], with `clauseCuts` and the remover.
  Future<String> cutFrom(String source, String clause, List<String> cut) async {
    final (path, sources, entries) = await entriesIn(source, clause, cut);
    expect(entries, everyElement(isNotNull));
    final removals = sources.clauseCuts(entries.nonNulls, tempDir.path).values;
    removeDeclarations([
      for (final removal in removals.toSet())
        .new(
          name: '',
          kind: removal.kind,
          filePath: removal.filePath,
          line: removal.range.startLine + 1,
          column: removal.range.startColumn + 1,
          isPrivate: true,
          range: removal.range,
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

  test('keeps at least one mixin of a type alias', () async {
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
    'reads from the outline whether a clause belongs to a type alias',
    () async {
      const source =
          '''
${types}class A = B with C;
class F extends B with C {}
''';
      final (_, _, aliased) = await entriesIn(source, 'with C;', ['C']);
      final (_, _, extended) = await entriesIn(source, 'with C {', ['C']);

      expect(aliased.single?.keepsOne, isTrue);
      expect(extended.single?.keepsOne, isFalse);
    },
  );

  test(
    'a type named outside a with or implements clause is no entry',
    () async {
      final (_, _, entries) = await entriesIn(
        '${types}class A extends B {}\n',
        'extends',
        ['B'],
      );

      expect(entries.single, isNull);
    },
  );
}
