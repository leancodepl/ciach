import 'dart:io';

import 'package:ciach/src/clause_entries.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/remover.dart';
import 'package:ciach/src/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Range;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('ciach_clauses_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// Returns [source] after removing the [cut] names from [clause] with
  /// `clauseCuts` and the remover.
  String cutFrom(
    String source,
    String clause,
    List<String> cut, {
    bool keepsOne = false,
  }) {
    final path = p.join(tempDir.path, 'lib.dart');
    File(path).writeAsStringSync(source);
    final clauseStart = source.indexOf(clause);
    final clauseEnd = clauseStart + clause.length;
    final entries = [
      for (final name in cut)
        (
          path: path,
          clauseStart: clauseStart,
          clauseEnd: clauseEnd,
          start: source.indexOf(RegExp('\\b$name\\b'), clauseStart),
          keepsOne: keepsOne,
        ),
    ];
    final removals = SourceIndex().clauseCuts(entries, tempDir.path).values;
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

  test('removes the only entry together with the keyword', () {
    expect(
      cutFrom('class A extends B with C {}\n', 'with C', ['C']),
      'class A extends B {}\n',
    );
  });

  test('removes entries together with the comma after them', () {
    expect(
      cutFrom('class A with C, D, E {}\n', 'with C, D, E', ['C', 'D']),
      'class A with E {}\n',
    );
  });

  test('removes entries at the end together with the comma before them', () {
    expect(
      cutFrom(
        'class A implements Comparable<A>, C, D;\n',
        'implements Comparable<A>, C, D',
        ['C', 'D'],
      ),
      'class A implements Comparable<A>;\n',
    );
  });

  test('removes the whole clause when every entry goes', () {
    expect(
      cutFrom('class A with C, D implements E {}\n', 'with C, D', ['C', 'D']),
      'class A implements E {}\n',
    );
  });

  test('keeps at least one mixin of a type alias', () {
    expect(
      cutFrom('class A = B with C, D;\n', 'with C, D', ['C'], keepsOne: true),
      'class A = B with D;\n',
    );
    expect(
      cutFrom('class A = B with C, D;\n', 'with C, D', [
        'C',
        'D',
      ], keepsOne: true),
      'class A = B with C, D;\n',
    );
  });

  test('removes entries separated by a comment and line breaks', () {
    expect(
      cutFrom(
        '''
class A
    implements
        C, // the first
        D,
        E {}
''',
        '''
implements
        C, // the first
        D,
        E''',
        ['C', 'E'],
      ),
      '''
class A
    implements
        D {}
''',
    );
  });

  test('reads from the outline whether a clause belongs to a type alias', () {
    const source = '''
class A = B with C;
class D extends B with C {}
''';
    final path = p.join(tempDir.path, 'lib.dart');
    File(path).writeAsStringSync(source);
    Range range(int line, int start, int end) => .new(
      start: .new(line: line, character: start),
      end: .new(line: line, character: end),
    );
    Outline declaration(String kind, String name, int line, int end) => .new(
      element: .new(kind: .fromWire(kind), name: name),
      range: range(line, 0, end),
      codeRange: range(line, 0, end),
      children: const [],
    );
    final unit = Outline(
      element: const .new(kind: .compilationUnit, name: ''),
      range: range(0, 0, 0),
      codeRange: range(0, 0, 0),
      children: [
        declaration('CLASS_TYPE_ALIAS', 'A', 0, 19),
        declaration('CLASS', 'D', 1, 27),
      ],
    );
    final sources = SourceIndex()..cacheLines(path, source.split('\n'));
    ClauseEntry? entryAt(int line, int clauseStart, int end) {
      final name = range(line, end - 1, end);
      sources.cacheSelectionRange(
        path,
        name.start,
        .new(
          range: name,
          parent: .new(
            range: range(line, clauseStart, end),
            parent: .new(range: range(line, 0, end + 1)),
          ),
        ),
      );
      return sources.clauseEntryAt(
        .new(uri: File(path).uri.toString(), range: name),
        'C',
        unit,
      );
    }

    expect(entryAt(0, 12, 18)?.keepsOne, isTrue);
    expect(entryAt(1, 18, 24)?.keepsOne, isFalse);
  });
}
