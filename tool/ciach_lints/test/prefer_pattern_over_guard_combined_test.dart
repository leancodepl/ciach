/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/pattern_over_guard.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(CombinedMovesTest);
  });
}

/// Tests of `when` clauses whose operands make several tests, which the fix
/// moves into the pattern together.
@reflectiveTest
class CombinedMovesTest() extends PatternOverGuardTest {
  Future<void> test_otherOperandsStay() async {
    await assertMoves(
      '''
void f(Object o, bool enabled) {
  if (o case final v when v is int && enabled) print(v);
}
''',
      'when v is int && enabled',
      replacement: 'final int v when enabled',
      fixed: '''
void f(Object o, bool enabled) {
  if (o case final int v when enabled) print(v);
}
''',
    );
  }

  Future<void> test_everyTestOnAVariableMoves() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v is int && v > 0) print(v);
}
''',
      'when v is int && v > 0',
      replacement: 'final int v && > 0',
      fixed: '''
void f(Object o) {
  if (o case final int v && > 0) print(v);
}
''',
    );
  }

  Future<void>
  test_comparisonsReplaceTheVariableInTheOrderOfTheirOperands() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final v when v > 0 && v < 10) print('digit');
}
''',
      'when v > 0 && v < 10',
      replacement: '> 0 && < 10',
      fixed: '''
void f(int n) {
  if (n case > 0 && < 10) print('digit');
}
''',
    );
  }

  Future<void> test_comparisonThatReplacesATypedVariableKeepsItsType() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v is int && v > 0) print('positive');
}
''',
      'when v is int && v > 0',
      replacement: 'int() && > 0',
      fixed: '''
void f(Object o) {
  if (o case int() && > 0) print('positive');
}
''',
    );
  }

  Future<void> test_pinnedValueMovesOnceTheTestAfterItHasMoved() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v == 'x' && v is String) print('x');
}
''',
      "when v == 'x' && v is String",
      replacement: "'x'",
      fixed: '''
void f(Object o) {
  if (o case 'x') print('x');
}
''',
    );
  }

  Future<void> test_pinnedNumberThatReplacesATypedVariableKeepsItsType() async {
    // `3` alone matches `3.0` too.
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v == 3 && v is int) print('three');
}
''',
      'when v == 3 && v is int',
      replacement: 'int() && 3',
      fixed: '''
void f(Object o) {
  if (o case int() && 3) print('three');
}
''',
    );
  }

  Future<void> test_typeTestThatNarrowsTheTypeMoves() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v is num && v is int) print(v);
}
''',
      'when v is num && v is int',
      replacement: 'final int v',
      fixed: '''
void f(Object o) {
  if (o case final int v) print(v);
}
''',
    );
  }

  Future<void> test_typeTestThatDoesNotNarrowTheTypeStays() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v is Comparable<Object> && v is Pattern) print(v);
}
''',
      'when v is Comparable<Object> && v is Pattern',
      replacement: 'final Comparable<Object> v when v is Pattern',
      fixed: '''
void f(Object o) {
  if (o case final Comparable<Object> v when v is Pattern) print(v);
}
''',
    );
  }

  Future<void> test_nullTestBeforeATypeTestLeavesNoNullCheck() async {
    await assertMoves(
      '''
void f(Map<String, Object?> m) {
  if (m['k'] case final v when v != null && v is int) print(v);
}
''',
      'when v != null && v is int',
      replacement: 'final int v',
      fixed: '''
void f(Map<String, Object?> m) {
  if (m['k'] case final int v) print(v);
}
''',
    );
  }

  Future<void> test_twoVariables() async {
    await assertMoves(
      r'''
void f((int?, Object) pair) {
  if (pair case (final a, final b) when a != null && b is String) {
    print('$a$b');
  }
}
''',
      'when a != null && b is String',
      replacement: '(final a?, final String b)',
      fixed: r'''
void f((int?, Object) pair) {
  if (pair case (final a?, final String b)) {
    print('$a$b');
  }
}
''',
    );
  }
}
