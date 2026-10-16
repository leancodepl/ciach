/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/switch_arms.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MergeIdenticalSwitchArmsTest);
  });
}

@reflectiveTest
class MergeIdenticalSwitchArmsTest() extends SwitchArmsTest {
  Future<void> test_twoArms() async {
    await assertMerges(
      '''
enum Kind { a, b, c }

int f(Kind k) => switch (k) {
  Kind.a => 1,
  Kind.b => 1,
  Kind.c => 2,
};
''',
      'Kind.b => 1',
      advice: "'Kind.a || Kind.b'",
      fixed: '''
enum Kind { a, b, c }

int f(Kind k) => switch (k) {
  Kind.a || Kind.b => 1,
  Kind.c => 2,
};
''',
    );
  }

  Future<void> test_threeArms() async {
    await assertMerges(
      '''
enum Kind { a, b, c, d }

int f(Kind k) => switch (k) {
  .a => 1,
  .b => 1,
  .c => 1,
  .d => 2,
};
''',
      '.b => 1',
      advice: "'.a || .b || .c'",
      fixed: '''
enum Kind { a, b, c, d }

int f(Kind k) => switch (k) {
  .a || .b || .c => 1,
  .d => 2,
};
''',
    );
  }

  Future<void> test_bodiesThatDifferOnlyInComments() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1 + 1, // Zero.
  1 => 1 /* One. */ + 1,
  _ => 0,
};
''',
      '1 => 1 /* One. */ + 1',
      advice: "'0 || 1'",
      fixed: '''
int f(int n) => switch (n) {
  0 || 1 => 1 /* One. */ + 1,
  _ => 0,
};
''',
    );
  }

  Future<void> test_sameVariables() async {
    await assertMerges(
      '''
int f((int, int) r) => switch (r) {
  (final a, 0) => a,
  (0, final a) => a,
  _ => 0,
};
''',
      '(0, final a) => a',
      advice: "'(final a, 0) || (0, final a)'",
      fixed: '''
int f((int, int) r) => switch (r) {
  (final a, 0) || (0, final a) => a,
  _ => 0,
};
''',
    );
  }

  Future<void> test_statementCases() async {
    await assertMerges(
      '''
void f(int n) {
  switch (n) {
    case 0:
      print('small');
    case 1:
      print('small');
    default:
      print('big');
  }
}
''',
      "case 1:\n      print('small');",
      advice: "'0 || 1'",
      fixed: '''
void f(int n) {
  switch (n) {
    case 0 || 1:
      print('small');
    default:
      print('big');
  }
}
''',
    );
  }

  Future<void> test_differentVariables() async {
    await assertNoDiagnostics('''
int f((int, int) r) => switch (r) {
  (final a, 0) => 0,
  (0, final b) => 0,
  _ => 1,
};
''');
  }

  Future<void> test_differentVariableTypes() async {
    await assertNoDiagnostics('''
int f(Object o) => switch (o) {
  final int v => v.hashCode,
  final String v => v.hashCode,
  _ => 0,
};
''');
  }

  Future<void> test_guardedArm() async {
    await assertNoDiagnostics('''
int f(int n, bool enabled) => switch (n) {
  0 when enabled => 1,
  1 => 1,
  _ => 0,
};
''');
  }

  Future<void> test_differentBodies() async {
    await assertNoDiagnostics('''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  _ => 3,
};
''');
  }

  Future<void> test_emptyCaseFallsThrough() async {
    await assertNoDiagnostics('''
void f(int n) {
  switch (n) {
    case 0:
    case 1:
      print('small');
    default:
      print('big');
  }
}
''');
  }
}
