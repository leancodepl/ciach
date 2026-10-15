/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/empty_fallback.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(AvoidEmptyCollectionFallbackTest);
  });
}

@reflectiveTest
class AvoidEmptyCollectionFallbackTest() extends EmptyFallbackTest {
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
      advice: "'if (xs != null)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  if (xs != null) {
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

  Future<void> test_loopOverPrivatePropertyBindsItWithoutUnderscores() async {
    await assertFallback(
      '''
class A {
  List<int>? _items;
}

void f(A a) {
  for (final x in a._items ?? <int>[]) print(x);
}
''',
      'a._items ?? <int>[]',
      advice: "'if (a._items case final items?)' around the loop",
      fixed: '''
class A {
  List<int>? _items;
}

void f(A a) {
  if (a._items case final items?) {
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
      advice: "'if (pairs != null)' around the loop",
      fixed: '''
void f(List<(int, int)>? pairs) {
  if (pairs != null) {
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
      advice: "'if (xs != null)' around the loop",
      fixed: r"""
void f(List<int>? xs) {
  if (xs != null) {
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
      advice: "'if (xs != null)' around the loop",
      fixed: '''
List<int> f(List<int>? xs) => [if (xs != null) for (final x in xs) x + 1];
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
      advice: "'if (xs != null)' around the loop",
      fixed: '''
void f(Set<int>? xs) {
  if (xs != null) {
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

  Future<void> test_loopOverFieldNamedOnlyWithUnderscoresHasNoFix() async {
    await assertFallback(
      '''
class A {
  List<int>? __;

  void f() {
    for (final x in __ ?? const <int>[]) print(x);
  }
}
''',
      '__ ?? const <int>[]',
      advice: "'if (… case final name?)' around the loop",
      fixed: null,
    );
  }

  Future<void> test_loopThatReadsTheFieldHasNoFix() async {
    // A call in the loop can change `items`, which the bound `items` would
    // hide.
    await assertFallback(
      '''
class A {
  List<int>? items;

  void clear() => items = null;

  void f() {
    for (final x in items ?? const <int>[]) {
      clear();
      print(items?.length ?? x);
    }
  }
}
''',
      'items ?? const <int>[]',
      advice: "'if (items case final items?)' around the loop",
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
      advice: "'if (xs != null)' around the loop",
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
