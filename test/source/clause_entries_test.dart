@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/source/clause_entries.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:test/test.dart';

import '../support/removal.dart';
import '../support/test_package.dart';

/// Cuts entries from `with` and `implements` clauses with the tokens, the
/// syntax nodes and the outline that the analyzer gives.
void main() {
  late TestPackage package;

  setUpAll(() => package = .new('clauses'));

  tearDownAll(() => package.dispose());

  /// Writes [source] to a new file and resolves it.
  Future<(String, SourceIndex)> index(String source) async {
    final path = package.writeNew(source);
    await package.files.of(path);
    return (
      path,
      SourceIndex(package.files)..cacheLines(path, source.split('\n')),
    );
  }

  /// Returns the clause entries for [names], searched for in [source] after the
  /// text [clause], as `clauseEntryAt` reads them.
  Future<(String, SourceIndex, List<ClauseEntry?>)> entriesIn(
    String source,
    String clause,
    List<String> names,
  ) async {
    final (path, sources) = await index(source);
    final unit = (await package.files.of(path))!.outline;
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
    return (
      path,
      sources,
      [
        for (final (i, range) in ranges.indexed)
          sources.clauseEntryAt(.new(path: path, range: range), names[i], unit),
      ],
    );
  }

  /// Returns [source] after removing the [cut] names from the clause that
  /// starts with [clause].
  Future<String> cutFrom(String source, String clause, List<String> cut) async {
    final (path, sources, entries) = await entriesIn(source, clause, cut);
    expect(entries, everyElement(isNotNull));
    final removals = sources.clauseCuts(entries.nonNulls, package.root).values;
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
    ], package.root);
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
      final (_, _, aliased) = await entriesIn(source, 'with C;', ['C']);
      final (_, _, extended) = await entriesIn(source, 'with C {', ['C']);

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
    final (_, _, entries) = await entriesIn(
      '${types}abstract class A implements Comparable<C> {}\n',
      'implements',
      ['C'],
    );

    expect(entries.single, isNull);
  });

  test(
    'returns no entry for a type named outside a with or implements clause',
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
