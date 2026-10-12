import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/removal.dart';

/// `--remove` on declarations whose range covers the whole node: functions,
/// classes, members, and what is coupled to or blocked with them.
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
    // A `--unused-union-members` finding is reported but never auto-removed:
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
}
