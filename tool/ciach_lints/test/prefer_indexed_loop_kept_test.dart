/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_indexed_loop.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferIndexedLoopKeptTest);
  });
}

/// The loops that `prefer_indexed_loop` leaves as they are, because the
/// rewrite could change what they do.
@reflectiveTest
class PreferIndexedLoopKeptTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferIndexedLoop();
    super.setUp();
  }

  Future<void> test_indexChangedInBodyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    if (xs[i] == 0) i++;
  }
}
''');
  }

  Future<void> test_elementWrittenInBodyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    xs[i] = xs[i] + 1;
  }
}
''');
  }

  Future<void> test_elementIncrementedInBodyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    xs[i]++;
  }
}
''');
  }

  Future<void> test_listUsedOtherwiseInBodyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    if (xs[i] == 0) xs.add(1);
  }
}
''');
  }

  Future<void> test_listReassignedInBodyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    print(xs[i]);
    xs = [];
  }
}
''');
  }

  Future<void> test_rootOfChainReassignedInBodyIsKept() async {
    await assertNoDiagnostics('''
class Box {
  final List<int> items = [];
}

void f(Box box) {
  for (var i = 0; i < box.items.length; i++) {
    print(box.items[i]);
    box = Box();
  }
}
''');
  }

  Future<void> test_otherListReadOnlyIsKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs, List<int> ys) {
  for (var i = 0; i < xs.length; i++) {
    print(ys[i]);
  }
}
''');
  }

  Future<void> test_otherBoundsAndStepsAreKept() async {
    await assertNoDiagnostics('''
void f(List<int> xs) {
  for (var i = 1; i < xs.length; i++) {
    print(xs[i]);
  }
  for (var i = 0; i <= xs.length - 1; i++) {
    print(xs[i]);
  }
  for (var i = 0; i < xs.length; i += 2) {
    print(xs[i]);
  }
  for (var i = 0; i < xs.length; i--) {
    print(xs[i]);
  }
  for (var i = 0, j = 0; i < xs.length; i++) {
    print(xs[i] + j);
  }
}
''');
  }

  Future<void> test_stringIsKept() async {
    await assertNoDiagnostics('''
void f(String s) {
  for (var i = 0; i < s.length; i++) {
    print(s[i]);
  }
}
''');
  }

  Future<void> test_listReturnedByCallIsKept() async {
    await assertNoDiagnostics('''
List<int> items() => [1, 2];

void f() {
  for (var i = 0; i < items().length; i++) {
    print(items()[i]);
  }
}
''');
  }

  Future<void> test_nullableListIsKept() async {
    await assertNoDiagnostics('''
void f(List<int>? xs) {
  for (var i = 0; i < (xs?.length ?? 0); i++) {
    print(xs![i]);
  }
}
''');
  }
}
