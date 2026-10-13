import 'dart:io';

import 'package:ciach/src/clause_entries.dart';
import 'package:ciach/src/remover.dart';
import 'package:ciach/src/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() => tempDir = Directory.systemTemp.createTempSync('ciach_clauses_'));
  tearDown(() => tempDir.deleteSync(recursive: true));

  /// [source] with the [cut] names cut out of its [clause], through
  /// `clauseCuts` and the remover.
  String cutFrom(String source, String clause, List<String> cut) {
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

  test('cuts the only entry with its keyword', () {
    expect(
      cutFrom('class A extends B with C {}\n', 'with C', ['C']),
      'class A extends B {}\n',
    );
  });

  test('cuts entries with the comma after them', () {
    expect(
      cutFrom('class A with C, D, E {}\n', 'with C, D, E', ['C', 'D']),
      'class A with E {}\n',
    );
  });

  test('cuts the last entries with the comma before them', () {
    expect(
      cutFrom(
        'class A implements Comparable<A>, C, D;\n',
        'implements Comparable<A>, C, D',
        ['C', 'D'],
      ),
      'class A implements Comparable<A>;\n',
    );
  });

  test('cuts every entry as the whole clause', () {
    expect(
      cutFrom('class A with C, D implements E {}\n', 'with C, D', ['C', 'D']),
      'class A implements E {}\n',
    );
  });

  test('cuts entries a comment and line breaks separate', () {
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
}
