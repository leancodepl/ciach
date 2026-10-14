import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/removal.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_remover_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  String applyRemoval(String content, List<UnusedDeclaration> decls) =>
      removeFrom(tempDir, content, decls);

  test('removes a top-level function along with its doc comment', () {
    const source = '''
void kept() {}

/// Never referenced.
void danglingFunction() {}

void alsoKept() {}
''';
    // `void danglingFunction() {}` is line index 3, columns 0..26.
    final result = applyRemoval(source, [
      decl(startLine: 3, startColumn: 0, endLine: 3, endColumn: 26, docLine: 2),
    ]);
    expect(result, isNot(contains('danglingFunction')));
    expect(result, isNot(contains('Never referenced')));
    expect(result, contains('void kept() {}'));
    expect(result, contains('void alsoKept() {}'));
  });

  group('a field or variable', () {
    /// The `variable` of `lib.dart` named at [line]:[column], with [cut].
    UnusedDeclaration declarator(int line, int column, DeclarationRange? cut) =>
        decl(
          startLine: line,
          startColumn: column,
          endLine: line,
          endColumn: column + 1,
          kind: .variable,
          cut: cut,
        );

    test('deletes its cut, extended to whole lines', () {
      const source = '''
class C {
  /// Doc.
  final int _unusedField = 0;

  void method() {}
}
''';
      final result = applyRemoval(source, [
        declarator(2, 12, (
          startLine: 1,
          startColumn: 2,
          endLine: 2,
          endColumn: 29,
        )),
      ]);
      expect(result, '''
class C {

  void method() {}
}
''');
    });

    test('deletes only its cut when the statement keeps other variables', () {
      const source = 'int a = 1, b = 2, c = 3;\n';
      final result = applyRemoval(source, [
        declarator(0, 11, (
          startLine: 0,
          startColumn: 11,
          endLine: 0,
          endColumn: 18,
        )),
      ]);
      expect(result, 'int a = 1, c = 3;\n');
    });

    test('stays when it has no cut', () {
      const source = 'int a = 1, b = 2;\n';
      expect(applyRemoval(source, [declarator(0, 4, null)]), source);
    });
  });

  test('collapses a fully-unused class into a single removal', () {
    const lines = [
      'class Kept {}',
      '',
      '/// Never referenced.',
      'class UnusedClass {',
      '  /// Never referenced.',
      '  void orphanMethod() {}',
      '}',
      '',
      'class AlsoKept {}',
      '',
    ];
    final source = lines.join('\n');

    final result = applyRemoval(source, [
      // Ranges start at the declaration's keyword (`class`/`void`), not at
      // the name — matching how the analysis server reports whole-node
      // kinds (only `field`/`variable`/`constant` exclude their prefix).
      decl(
        startLine: 3,
        startColumn: 0,
        endLine: 6,
        endColumn: 1,
        kind: .class$,
        docLine: 2,
      ),
      decl(
        startLine: 5,
        startColumn: 2,
        endLine: 5,
        endColumn: 2 + 'void orphanMethod() {}'.length,
        kind: .method,
        docLine: 4,
        docColumn: 2,
      ),
    ]);
    expect(result, isNot(contains('UnusedClass')));
    expect(result, isNot(contains('orphanMethod')));
    expect(result, contains('class Kept {}'));
    expect(result, contains('class AlsoKept {}'));
    expectBalanced(result);
  });

  test('a variable both reported and coupled is removed once', () {
    // `right` is a finding, and is also coupled to the dead member it
    // overrides; `left` is coupled too. All three entries have the whole
    // statement as their cut.
    const source = '''
class Pair {
  final int left = 1, right = 2;
}
''';
    const statement = (startLine: 1, startColumn: 2, endLine: 1, endColumn: 32);
    const right = UnusedDeclaration(
      name: 'right',
      kind: .field,
      filePath: 'lib.dart',
      line: 2,
      column: 23,
      isPrivate: false,
      range: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
      cut: statement,
      coupledRemovals: [
        // `right` again, coupled to the member it overrides.
        (
          filePath: 'lib.dart',
          kind: .field,
          range: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
          fullRange: (startLine: 1, startColumn: 22, endLine: 1, endColumn: 31),
          cut: statement,
        ),
        // `left`, the statement's other variable.
        (
          filePath: 'lib.dart',
          kind: .field,
          range: (startLine: 1, startColumn: 12, endLine: 1, endColumn: 20),
          fullRange: (startLine: 1, startColumn: 12, endLine: 1, endColumn: 20),
          cut: statement,
        ),
      ],
    );
    expect(applyRemoval(source, [right]), '''
class Pair {
}
''');
  });
  test(
    'a coupled declarator is taken out of a statement that keeps the rest',
    () {
      // The implementing declarator shares its statement with a live one: the
      // statement stays, one declarator goes.
      const source = '''
abstract class Halved {
  int get dead;
}

class Mixed implements Halved {
  final int dead = 1, live = 2;
}
''';
      // `int get dead;` is line 1, cols 2..15. The cut of its override is
      // `dead = 1, ` on line 5, cols 12..22, up to the next variable.
      const member = UnusedDeclaration(
        name: 'dead',
        kind: .property,
        filePath: 'lib.dart',
        line: 2,
        column: 11,
        isPrivate: false,
        range: (startLine: 1, startColumn: 2, endLine: 1, endColumn: 15),
        coupledRemovals: [
          (
            filePath: 'lib.dart',
            kind: .field,
            range: (startLine: 5, startColumn: 12, endLine: 5, endColumn: 20),
            fullRange: (
              startLine: 5,
              startColumn: 12,
              endLine: 5,
              endColumn: 20,
            ),
            cut: (startLine: 5, startColumn: 12, endLine: 5, endColumn: 22),
          ),
        ],
      );
      final result = applyRemoval(source, [member]);
      expect(result, '''
abstract class Halved {
}

class Mixed implements Halved {
  final int live = 2;
}
''');
    },
  );

  test('removing nothing leaves the file untouched', () {
    const source = 'void kept() {}\n';
    expect(applyRemoval(source, const []), source);
  });

  test(
    'a coupled removal deletes a second whole-node span in the same file',
    () {
      // A dead StatefulWidget and its paired State subclass: removing only the
      // widget would leave `State<DeadWidget>` dangling, so the State's span is
      // coupled to the widget's removal.
      const source = '''
class DeadWidget {
  const DeadWidget();

  State<DeadWidget> createState() => _DeadWidgetState();
}

class _DeadWidgetState extends State<DeadWidget> {}

class Kept {}
''';
      // `class DeadWidget { ... }` spans line 0 col 0 .. line 4 col 1.
      // `class _DeadWidgetState ... {}` is line 6, cols 0..51.
      const widget = UnusedDeclaration(
        name: 'DeadWidget',
        kind: .class$,
        filePath: 'lib.dart',
        line: 1,
        column: 7,
        isPrivate: false,
        range: (startLine: 0, startColumn: 0, endLine: 4, endColumn: 1),
        coupledRemovals: [
          (
            filePath: 'lib.dart',
            kind: .class$,
            range: (startLine: 6, startColumn: 0, endLine: 6, endColumn: 51),
            fullRange: (
              startLine: 6,
              startColumn: 0,
              endLine: 6,
              endColumn: 51,
            ),
            cut: null,
          ),
        ],
      );
      final result = applyRemoval(source, [widget]);
      expect(result, isNot(contains('DeadWidget')));
      expect(result, isNot(contains('_DeadWidgetState')));
      expect(result, contains('class Kept {}'));
      expectBalanced(result);
    },
  );

  test('a report-only (removalBlocked) finding is left in place, and nothing '
      'coupled to it is removed either', () {
    // A `--also union-members` finding is reported but never auto-removed:
    // the remover must skip the declaration entirely — including any span that
    // was coupled to it — so the source is left untouched.
    const source = '''
sealed class S {}

class Kept extends S {}

class Dead extends S {}

String describe(S s) => switch (s) {
  Kept() => 'kept',
  Dead() => 'dead',
};
''';
    const dead = UnusedDeclaration(
      name: 'Dead',
      kind: .class$,
      filePath: 'lib.dart',
      line: 5,
      column: 7,
      isPrivate: false,
      range: (startLine: 4, startColumn: 0, endLine: 4, endColumn: 23),
      removalBlocked: true,
      // Even if a coupled span were attached, a blocked finding is skipped
      // whole — so the arm must survive too.
      coupledRemovals: [
        (
          filePath: 'lib.dart',
          kind: .class$,
          range: (startLine: 8, startColumn: 2, endLine: 9, endColumn: 0),
          fullRange: (startLine: 8, startColumn: 2, endLine: 9, endColumn: 0),
          cut: null,
        ),
      ],
    );

    final result = applyRemoval(source, [dead]);
    expect(result, equals(source), reason: 'report-only: nothing removed');
    expect(result, contains('class Dead extends S {}'));
    expect(result, contains("Dead() => 'dead'"));
  });

  test(
    'a removalBlocked enum value is reported but left in place by --remove',
    () {
      // The remove-safety guard for an about-to-be-emptied enum marks the value
      // finding `removalBlocked`; the remover must leave the enum untouched so it
      // keeps a value (an empty `enum {}` would not compile).
      const source = '''
enum Status {
  only,
}

Status? statusHolder;
''';
      // `only` is line index 1, columns 2..6.
      const blockedValue = UnusedDeclaration(
        name: 'only',
        kind: .enum$,
        filePath: 'lib.dart',
        line: 2,
        column: 3,
        isPrivate: false,
        isEnumValue: true,
        range: (startLine: 1, startColumn: 2, endLine: 1, endColumn: 6),
        removalBlocked: true,
      );

      final result = applyRemoval(source, [blockedValue]);
      expect(result, equals(source), reason: 'report-only: nothing removed');
      expect(result, contains('only,'));
    },
  );

  test(
    'a removalBlocked constructor is reported but left in place by --remove',
    () {
      // The sole-constructor guards (final fields / super forwarding) mark the
      // constructor finding `removalBlocked`; removing it would leave an implicit
      // default constructor that strands final fields or breaks `super()`.
      const source = '''
class Holder {
  const Holder(this.label);

  final String label;
}

Holder? holderRef;
''';
      // `const Holder(this.label);` is line index 1, columns 2..27.
      const blockedCtor = UnusedDeclaration(
        name: 'new',
        kind: .constructor,
        filePath: 'lib.dart',
        line: 2,
        column: 3,
        isPrivate: false,
        container: 'Holder',
        range: (startLine: 1, startColumn: 2, endLine: 1, endColumn: 27),
        removalBlocked: true,
      );

      final result = applyRemoval(source, [blockedCtor]);
      expect(result, equals(source), reason: 'report-only: nothing removed');
      expect(result, contains('const Holder(this.label);'));
    },
  );

  test('removes a dead class declared with a primary constructor and a `;` '
      'body', () {
    // The whole declaration is the header; the class range covers the `;`.
    const source = '''
class Kept(var int x);

/// Never referenced.
class DeadPoint(var int x, var int y);

int useKept() => Kept(1).x;
''';
    // `class DeadPoint(var int x, var int y);` is line index 3, columns 0..38.
    final result = applyRemoval(source, [
      decl(
        startLine: 3,
        startColumn: 0,
        endLine: 3,
        endColumn: 38,
        kind: .class$,
        docLine: 2,
      ),
    ]);
    expect(result, isNot(contains('DeadPoint')));
    expect(result, isNot(contains('Never referenced')));
    expect(result, contains('class Kept(var int x);'));
    expect(result, contains('int useKept() => Kept(1).x;'));
    expectBalanced(result);
  });

  test(
    'removes an abbreviated `new`/`factory` constructor from a class body',
    () {
      const source = '''
class Registry {
  new() : tag = null;

  /// Never invoked.
  new deadNamed() : tag = null;

  /// Never invoked either.
  factory deadRedirect() = Registry;

  final String? tag;
}
''';
      final result = applyRemoval(source, [
        // `new deadNamed() : tag = null;` is line index 4, columns 2..30.
        decl(
          startLine: 4,
          startColumn: 2,
          endLine: 4,
          endColumn: 30,
          kind: .constructor,
          docLine: 3,
          docColumn: 2,
        ),
        // `factory deadRedirect() = Registry;` is line index 7, columns 2..35.
        decl(
          startLine: 7,
          startColumn: 2,
          endLine: 7,
          endColumn: 35,
          kind: .constructor,
          docLine: 6,
          docColumn: 2,
        ),
      ]);
      expect(result, isNot(contains('deadNamed')));
      expect(result, isNot(contains('deadRedirect')));
      expect(result, contains('new() : tag = null;'));
      expect(result, contains('final String? tag;'));
      expectBalanced(result);
    },
  );

  test('a file it cannot rewrite stops it, naming what it already rewrote', () {
    File(
      p.join(tempDir.path, 'lib.dart'),
    ).writeAsStringSync('void a() {}\nvoid b() {}\n');
    // A directory where the next file should be: reading it fails.
    Directory(p.join(tempDir.path, 'other.dart')).createSync();
    const unreadable = UnusedDeclaration(
      name: 'c',
      kind: .function,
      filePath: 'other.dart',
      line: 1,
      column: 6,
      isPrivate: false,
      range: (startLine: 0, startColumn: 0, endLine: 0, endColumn: 11),
    );

    expect(
      () => removeDeclarations([
        decl(startLine: 0, startColumn: 0, endLine: 0, endColumn: 11),
        unreadable,
      ], tempDir.path),
      throwsA(
        isA<RemovalException>()
            .having((e) => e.filePath, 'filePath', 'other.dart')
            .having((e) => e.changedFiles, 'changedFiles', ['lib.dart']),
      ),
    );
    expect(
      File(p.join(tempDir.path, 'lib.dart')).readAsStringSync(),
      'void b() {}\n',
    );
  });

  group('a comment above removed code', () {
    /// Removes [decls] from [content] in `lib.dart` and returns the lines of
    /// the comments it kept above them.
    List<int> leftCommentLines(String content, List<UnusedDeclaration> decls) {
      File(p.join(tempDir.path, 'lib.dart')).writeAsStringSync(content);
      return [
        for (final (:filePath, :line) in removeDeclarations(
          decls,
          tempDir.path,
        ).leftComments)
          if (filePath == 'lib.dart') line,
      ];
    }

    test('stays and is listed by its line after removal', () {
      const source = '''
void a() {}

// About b,
// on two lines.
/// Doc of b.
void b() {}

void c() {}
''';
      final lines = leftCommentLines(source, [
        decl(startLine: 0, startColumn: 0, endLine: 0, endColumn: 11),
        decl(
          startLine: 5,
          startColumn: 0,
          endLine: 5,
          endColumn: 11,
          docLine: 4,
        ),
      ]);
      expect(File(p.join(tempDir.path, 'lib.dart')).readAsStringSync(), '''

// About b,
// on two lines.

void c() {}
''');
      expect(lines, [2]);
    });

    test('is not listed with a blank line after it', () {
      const source = '''
// Section.

void a() {}

void b() {}
''';
      expect(
        leftCommentLines(source, [
          decl(startLine: 2, startColumn: 0, endLine: 2, endColumn: 11),
        ]),
        isEmpty,
      );
    });

    test('is not listed when it is a ciach marker or goes too', () {
      const source = '''
// ciach:ignore-end
void a() {}

class C {
  // About m.
  void m() {}
}

void b() {}
''';
      expect(
        leftCommentLines(source, [
          decl(startLine: 1, startColumn: 0, endLine: 1, endColumn: 11),
          decl(
            startLine: 3,
            startColumn: 0,
            endLine: 6,
            endColumn: 1,
            kind: .class$,
          ),
          decl(
            startLine: 5,
            startColumn: 2,
            endLine: 5,
            endColumn: 13,
            kind: .method,
          ),
        ]),
        isEmpty,
      );
    });

    test('is not listed when its file is deleted', () {
      const source = '''
import 'dart:math';

// About a.
int a() => max(1, 2);
''';
      expect(
        leftCommentLines(source, [
          decl(startLine: 3, startColumn: 0, endLine: 3, endColumn: 20),
        ]),
        isEmpty,
      );
      expect(File(p.join(tempDir.path, 'lib.dart')).existsSync(), isFalse);
    });
  });
}
