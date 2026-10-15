/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/avoid_empty_collection_fallback.dart';
import 'package:ciach_lints/src/promotion.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PromotionTest);
  });
}

@reflectiveTest
class PromotionTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    // `AnalysisRuleTest` needs a rule to set up, but these tests don't run
    // one.
    rule = AvoidEmptyCollectionFallback();
    super.setUp();
  }

  /// Returns whether [isPromotable] holds for the argument of the one
  /// `check(…)` call in [code], after checking that [code] compiles.
  Future<bool> promotes(String code) async {
    final file = newFile(
      testFile.path,
      '$code\nvoid check(Object? value) {}\n',
    );
    final unit = await resolveFile(file.path);
    expect(unit.diagnostics, isEmpty);
    final argument = _CheckArgument();
    unit.unit.accept(argument);
    return isPromotable(argument.value!);
  }

  Future<void> test_localVariableIsPromotable() async {
    expect(
      await promotes('''
void f(List<List<int>?> lists) {
  final xs = lists.first;
  check(xs);
}
'''),
      isTrue,
    );
  }

  Future<void> test_parameterIsPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  check(xs);
}
'''),
      isTrue,
    );
  }

  Future<void> test_namedParameterIsPromotable() async {
    expect(
      await promotes('''
void f({List<int>? xs}) {
  check(xs);
}
'''),
      isTrue,
    );
  }

  Future<void> test_parameterThatItsFunctionAssignsIsPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  xs = xs?.toList();
  check(xs);
}
'''),
      isTrue,
    );
  }

  Future<void> test_parameterThatAClosureAssignsIsNotPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  void reset() => xs = null;
  check(xs);
  reset();
}
'''),
      isFalse,
    );
  }

  Future<void>
  test_parameterThatAClosureAssignsWithAPatternIsNotPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs, List<int>? ys) {
  void reset() => (xs, ys) = (null, null);
  check(xs);
  reset();
}
'''),
      isFalse,
    );
  }

  Future<void> test_parameterReadInAClosureIsPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  void g() => check(xs);
  g();
}
'''),
      isTrue,
    );
  }

  Future<void>
  test_parameterReadInAClosureAndAssignedByItsFunctionIsPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  void g() => check(xs);
  xs = null;
  g();
}
'''),
      isTrue,
    );
  }

  Future<void>
  test_parameterThatTheReadingClosureAssignsIsNotPromotable() async {
    expect(
      await promotes('''
void f(List<int>? xs) {
  void g() {
    xs = xs?.toList();
    check(xs);
  }

  g();
}
'''),
      isFalse,
    );
  }

  Future<void> test_closureParameterThatTheClosureAssignsIsPromotable() async {
    expect(
      await promotes('''
void f(List<List<int>?> lists) {
  lists.forEach((xs) {
    xs = xs?.toList();
    check(xs);
  });
}
'''),
      isTrue,
    );
  }

  Future<void> test_methodParameterThatTheMethodAssignsIsPromotable() async {
    expect(
      await promotes('''
class A {
  void f(List<int>? xs) {
    xs = xs?.toList();
    check(xs);
  }
}
'''),
      isTrue,
    );
  }

  Future<void>
  test_constructorParameterThatTheConstructorAssignsIsPromotable() async {
    expect(
      await promotes('''
class A {
  A(List<int>? xs) {
    xs = xs?.toList();
    check(xs);
  }
}
'''),
      isTrue,
    );
  }

  Future<void> test_privateFinalFieldIsPromotable() async {
    expect(
      await promotes('''
class A {
  A(this._items);

  final List<int>? _items;

  void f() => check(_items);
}
'''),
      isTrue,
    );
  }

  Future<void> test_privateFinalFieldOfThisIsPromotable() async {
    expect(
      await promotes('''
class A {
  A(this._items);

  final List<int>? _items;

  void f() => check(this._items);
}
'''),
      isTrue,
    );
  }

  Future<void> test_privateFinalFieldsOfAParameterArePromotable() async {
    expect(
      await promotes('''
class B {
  B(this._items);

  final List<int>? _items;
}

class A {
  A(this._b);

  final B _b;
}

void f(A a) => check(a._b._items);
'''),
      isTrue,
    );
  }

  Future<void>
  test_privateFinalFieldOfAParameterThatAClosureAssignsIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  A(this._items);

  final List<int>? _items;
}

void f(A a) {
  void reset() => a = A(null);
  check(a._items);
  reset();
}
'''),
      isFalse,
    );
  }

  Future<void> test_privateFinalFieldOfAPublicFieldIsNotPromotable() async {
    expect(
      await promotes('''
class B {
  B(this._items);

  final List<int>? _items;
}

class A {
  A(this.b);

  final B b;
}

void f(A a) => check(a.b._items);
'''),
      isFalse,
    );
  }

  Future<void> test_privateFieldThatIsNotFinalIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  List<int>? _items;

  void f() => check(_items);
}
'''),
      isFalse,
    );
  }

  Future<void> test_privateGetterIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  List<int>? get _items => null;

  void f() => check(_items);
}
'''),
      isFalse,
    );
  }

  Future<void> test_publicFinalFieldOfAParameterIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  A(this.items);

  final List<int>? items;
}

void f(A a) => check(a.items);
'''),
      isFalse,
    );
  }

  Future<void> test_publicFinalFieldOfThisIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  A(this.items);

  final List<int>? items;

  void f() => check(this.items);
}
'''),
      isFalse,
    );
  }

  Future<void> test_nullAwareReadOfAPrivateFinalFieldIsNotPromotable() async {
    expect(
      await promotes('''
class A {
  A(this._items);

  final List<int>? _items;
}

void f(A? a) => check(a?._items);
'''),
      isFalse,
    );
  }
}

/// Finds the argument of a `check(…)` call.
class _CheckArgument() extends RecursiveAstVisitor<void> {
  Expression? value;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node case MethodInvocation(
      methodName: SimpleIdentifier(name: 'check'),
      argumentList: ArgumentList(arguments: [final Expression argument]),
    )) {
      value = argument;
    }
    super.visitMethodInvocation(node);
  }
}
