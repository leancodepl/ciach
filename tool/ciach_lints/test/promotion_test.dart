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
    defineReflectiveTests(PromotionTest);
  });
}

/// Tests `isPromotable` through the fix of `avoid_empty_collection_fallback`,
/// which writes `if (xs != null)` only for an `xs` that the check promotes.
/// The fixed code compiles only when the check really promotes `xs`.
@reflectiveTest
class PromotionTest() extends EmptyFallbackTest {
  Future<void> test_loopThatAssignsTheParameter() async {
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
      advice: "'if (xs != null)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  if (xs != null) {
    for (final x in xs) {
      xs = null;
      print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverLocalVariable() async {
    await assertFallback(
      '''
List<int>? make() => null;

void f() {
  final xs = make();
  for (final x in xs ?? const []) {
    print(x);
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs != null)' around the loop",
      fixed: '''
List<int>? make() => null;

void f() {
  final xs = make();
  if (xs != null) {
    for (final x in xs) {
      print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverParameterThatAClosureAssigns() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  void reset() => xs = null;
  for (final x in xs ?? const []) {
    print(x);
  }
  reset();
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  void reset() => xs = null;
  if (xs case final xs?) {
    for (final x in xs) {
      print(x);
    }
  }
  reset();
}
''',
    );
  }

  Future<void> test_loopOverParameterThatAClosureAssignsWithAPattern() async {
    await assertFallback(
      '''
void f(List<int>? xs, List<int>? ys) {
  void reset() => (xs, ys) = (null, null);
  for (final x in xs ?? const []) {
    print(x);
  }
  reset();
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
void f(List<int>? xs, List<int>? ys) {
  void reset() => (xs, ys) = (null, null);
  if (xs case final xs?) {
    for (final x in xs) {
      print(x);
    }
  }
  reset();
}
''',
    );
  }

  Future<void> test_loopInClosureOverAssignedParameter() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  xs = xs?.toList();
  void g() {
    for (final x in xs ?? const []) {
      print(x);
    }
  }

  g();
}
''',
      'xs ?? const []',
      advice: "'if (xs case final xs?)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  xs = xs?.toList();
  void g() {
    if (xs case final xs?) {
      for (final x in xs) {
        print(x);
      }
    }
  }

  g();
}
''',
    );
  }

  Future<void> test_loopInClosureOverUnassignedParameter() async {
    await assertFallback(
      '''
void f(List<int>? xs) {
  void g() {
    for (final x in xs ?? const []) {
      print(x);
    }
  }

  g();
}
''',
      'xs ?? const []',
      advice: "'if (xs != null)' around the loop",
      fixed: '''
void f(List<int>? xs) {
  void g() {
    if (xs != null) {
      for (final x in xs) {
        print(x);
      }
    }
  }

  g();
}
''',
    );
  }

  Future<void> test_loopInClosureOverItsOwnAssignedParameter() async {
    await assertFallback(
      '''
void f(List<List<int>?> lists) {
  lists.forEach((xs) {
    xs = xs?.toList();
    for (final x in xs ?? const []) {
      print(x);
    }
  });
}
''',
      'xs ?? const []',
      advice: "'if (xs != null)' around the loop",
      fixed: '''
void f(List<List<int>?> lists) {
  lists.forEach((xs) {
    xs = xs?.toList();
    if (xs != null) {
      for (final x in xs) {
        print(x);
      }
    }
  });
}
''',
    );
  }

  Future<void> test_loopOverAssignedParameterOfMethod() async {
    await assertFallback(
      '''
class A {
  void f(List<int>? xs) {
    xs = xs?.toList();
    for (final x in xs ?? const []) print(x);
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs != null)' around the loop",
      fixed: '''
class A {
  void f(List<int>? xs) {
    xs = xs?.toList();
    if (xs != null) {
      for (final x in xs) print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverAssignedParameterOfConstructor() async {
    await assertFallback(
      '''
class A {
  A(List<int>? xs) {
    xs = xs?.toList();
    for (final x in xs ?? const []) print(x);
  }
}
''',
      'xs ?? const []',
      advice: "'if (xs != null)' around the loop",
      fixed: '''
class A {
  A(List<int>? xs) {
    xs = xs?.toList();
    if (xs != null) {
      for (final x in xs) print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverPrivateField() async {
    await assertFallback(
      '''
class A {
  A(this._items);

  final List<int>? _items;

  void f() {
    for (final x in _items ?? const <int>[]) print(x);
  }
}
''',
      '_items ?? const <int>[]',
      advice: "'if (_items != null)' around the loop",
      fixed: '''
class A {
  A(this._items);

  final List<int>? _items;

  void f() {
    if (_items != null) {
      for (final x in _items) print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverPrivateFieldOfThis() async {
    await assertFallback(
      '''
class A {
  A(this._items);

  final List<int>? _items;

  void f() {
    for (final x in this._items ?? const <int>[]) print(x);
  }
}
''',
      'this._items ?? const <int>[]',
      advice: "'if (this._items != null)' around the loop",
      fixed: '''
class A {
  A(this._items);

  final List<int>? _items;

  void f() {
    if (this._items != null) {
      for (final x in this._items) print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverPrivateFieldsOfParameter() async {
    await assertFallback(
      '''
class B {
  B(this._items);

  final List<int>? _items;
}

class A {
  A(this._b);

  final B _b;
}

void f(A a) {
  for (final x in a._b._items ?? const <int>[]) print(x);
}
''',
      'a._b._items ?? const <int>[]',
      advice: "'if (a._b._items != null)' around the loop",
      fixed: '''
class B {
  B(this._items);

  final List<int>? _items;
}

class A {
  A(this._b);

  final B _b;
}

void f(A a) {
  if (a._b._items != null) {
    for (final x in a._b._items) print(x);
  }
}
''',
    );
  }

  Future<void> test_loopOverPrivateFieldThatIsNotFinal() async {
    await assertFallback(
      '''
class A {
  List<int>? _items;

  void f() {
    for (final x in _items ?? const <int>[]) print(x);
  }
}
''',
      '_items ?? const <int>[]',
      advice: "'if (_items case final items?)' around the loop",
      fixed: '''
class A {
  List<int>? _items;

  void f() {
    if (_items case final items?) {
      for (final x in items) print(x);
    }
  }
}
''',
    );
  }

  Future<void> test_loopOverNullAwarePrivateField() async {
    await assertFallback(
      '''
class A {
  A(this._items);

  final List<int>? _items;
}

void f(A? a) {
  for (final x in a?._items ?? const <int>[]) print(x);
}
''',
      'a?._items ?? const <int>[]',
      advice: "'if (a?._items case final items?)' around the loop",
      fixed: '''
class A {
  A(this._items);

  final List<int>? _items;
}

void f(A? a) {
  if (a?._items case final items?) {
    for (final x in items) print(x);
  }
}
''',
    );
  }
}
