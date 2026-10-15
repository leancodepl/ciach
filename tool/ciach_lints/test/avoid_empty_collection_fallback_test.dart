/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/avoid_empty_collection_fallback.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidEmptyCollectionFallbackTest);
  });
}

@reflectiveTest
class AvoidEmptyCollectionFallbackTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = AvoidEmptyCollectionFallback();
    super.setUp();
  }

  /// Checks that [flagged] in [code] is flagged with [advice] in the
  /// correction, and that the fix turns [code] into [fixed], or offers
  /// nothing when [fixed] is `null`.
  Future<void> assertFallback(
    String code,
    String flagged, {
    required String advice,
    required String? fixed,
  }) async {
    await assertDiagnostics(code, [
      lint(code.indexOf(flagged), flagged.length, correctionContains: advice),
    ]);
    expect(
      await applyFixes(
        code,
        AvoidEmptyCollectionFallback.code,
        SkipNullCollection.new,
      ),
      fixed,
    );
  }

  Future<void> test_loopOverParameter() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  for (final x in xs ?? const []) {
    print(x);
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  if (xs case final xs?) {
    for (final x in xs) {
      print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverProperty() async {
    await assertFallback(
      '''
class A {
  List<int>? items;
}

void f(A a) {
  for (final x in a.items ?? <int>[]) print(x);
}
''',
      'a.items ?? <int>[]',
      advice: "'if (a.items case final items?)' around the loop",
      fixed: '''
class A {
  List<int>? items;
}

void f(A a) {
  if (a.items case final items?) {
    for (final x in items) print(x);
  }
}
''',
    );
  }

  Future<void> test_loopWithPattern() async {
    await assertFallback(
      '''
void f(List<(int, int)>? pairs) {
  for (final (a, b) in pairs ?? const <(int, int)>[]) {
    print(a + b);
  }
}
''',
      'pairs ?? const <(int, int)>[]',
      advice: "'if (pairs case final pairs?)' around the loop",
      fixed: '''
void f(List<(int, int)>? pairs) {
  if (pairs case final pairs?) {
    for (final (a, b) in pairs) {
      print(a + b);
    }
  }
}
''',
    );
  }

  Future<void> test_loopKeepsMultilineStrings() async {
    await assertFallback(
      r"""
void f(List<int>? xs) {
  for (final x in xs ?? const []) {
    print('''
$x''');
  }
}
""",
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: r"""
void f(List<int>? xs) {
  if (xs case final xs?) {
    for (final x in xs) {
      print('''
$x''');
    }
  }
}
""",
    );
  }

  Future<void> test_loopElement() async {
    await assertFallback(
      '''
List<int> f(List<int>? xs) => [for (final x in xs ?? const <int>[]) x + 1];
''',
      'xs ?? const <int>[]',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
List<int> f(List<int>? xs) => [if (xs case final xs?) for (final x in xs) x + 1];
''',
    );
  }

  Future<void> test_parenthesized() async {
    await assertFallback(
      '''
void f(Set<int>? xs) {
  for (final x in (xs ?? {})) {
    print(x);
  }
}
''',
      '(xs ?? {})',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
void f(Set<int>? xs) {
  if (xs case final xs?) {
    for (final x in xs) {
      print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_spread() async {
    await assertFallback(
      '''
List<int> f(List<int>? xs) => [0, ...(xs ?? [])];
''',
      '(xs ?? [])',
      advice: "'...?xs'",
      fixed: '''
List<int> f(List<int>? xs) => [0, ...?xs];
''',
    );
  }

  Future<void> test_spreadOfMap() async {
    await assertFallback(
      '''
Map<String, int> f(Map<String, int>? m) => {...(m ?? const {})};
''',
      '(m ?? const {})',
      advice: "'...?m'",
      fixed: '''
Map<String, int> f(Map<String, int>? m) => {...?m};
''',
    );
  }

  Future<void> test_callTargetHasNoFix() async {
    await assertFallback(
      '''
Iterable<int> f(List<int>? xs) => (xs ?? const []).map((x) => x + 1);
''',
      '(xs ?? const [])',
      advice: "a null-aware call on 'xs'",
      fixed: null,
    );
  }

  Future<void> test_propertyTargetHasNoFix() async {
    await assertFallback(
      '''
int f(List<int>? xs) => (xs ?? const []).length;
''',
      '(xs ?? const [])',
      advice: "a null-aware call on 'xs'",
      fixed: null,
    );
  }

  Future<void> test_loopThatReadsTheNameHasNoFix() async {
    await assertFallback(
      '''
class A {
  List<int>? items;
}

void f(A a, List<int> items) {
  for (final x in a.items ?? const <int>[]) {
    items.add(x);
  }
}
''',
      'a.items ?? const <int>[]',
      advice: "'if (a.items case final items?)' around the loop",
      fixed: null,
    );
  }

  Future<void> test_loopThatAssignsTheVariableHasNoFix() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  for (final x in xs ?? const []) {
    xs = null;
    print(x);
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: null,
    );
  }

  Future<void> test_labeledLoopHasNoFix() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  outer:
  for (final x in xs ?? const []) {
    if (x > 0) continue outer;
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: null,
    );
  }

  Future<void> test_unnamedIterableHasNoFix() async {
    await assertFallback(
      '''
void f(List<List<int>?> xss) {
  for (final x in xss[0] ?? const []) {
    print(x);
  }
}
''',
      'xss[0] ?? const []',
      advice: "an 'if (… case final name?)' around the loop",
      fixed: null,
    );
  }

  Future<void> test_storedFallback() async {
    await assertNoDiagnostics('''
List<int> f(List<int>? xs) {
  final ys = xs ?? const [];
  return ys;
}
''');
  }

  Future<void> test_nonEmptyFallback() async {
    await assertNoDiagnostics('''
void f(List<int>? xs) {
  for (final x in xs ?? const [1]) {
    print(x);
  }
}
''');
  }

  Future<void> test_nullAwareSpread() async {
    await assertNoDiagnostics('''
List<int> f(List<int>? xs) => [...?xs];
''');
  }
}
