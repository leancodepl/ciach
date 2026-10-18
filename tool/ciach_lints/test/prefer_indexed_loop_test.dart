/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_indexed_loop.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferIndexedLoopTest);
  });
}

/// Stands in for `Iterable.indexed`, which the analyzer's mock SDK lacks.
const _indexed = '''
extension Indexed<T> on Iterable<T> {
  Iterable<(int, T)> get indexed sync* {
    var index = 0;
    for (final element in this) {
      yield (index++, element);
    }
  }
}
''';

@reflectiveTest
class PreferIndexedLoopTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferIndexedLoop();
    super.setUp();
  }

  /// Checks that the header of the first `for` loop in [code], from `for` to
  /// its `)`, is flagged with [header] as the suggestion, and that the fix
  /// turns [code] into [fixed], which compiles with no diagnostics. Both get
  /// [_indexed] at the end.
  Future<void> assertRewrites(
    String code, {
    required String header,
    required String fixed,
  }) async {
    final flagged = '$code$_indexed';
    final start = flagged.indexOf('for (');
    final end = _headerEnd(flagged, start);
    await assertDiagnostics(flagged, [
      lint(start, end - start, messageContainsAll: ["'for ($header)'"]),
    ]);
    expect(
      await applyFixes(flagged, PreferIndexedLoop.code, LoopOverElements.new),
      '$fixed$_indexed',
    );
    final file = newFile('$testPackageLibPath/fixed.dart', '$fixed$_indexed');
    expect((await resolveFile(file.path)).diagnostics, isEmpty);
  }

  Future<void> test_loopThatOnlyReadsElementsBecomesForIn() async {
    await assertRewrites(
      '''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    print(xs[i]);
  }
}
''',
      header: 'final x in xs',
      fixed: '''
void f(List<int> xs) {
  for (final x in xs) {
    print(x);
  }
}
''',
    );
  }

  Future<void> test_loopThatUsesIndexBecomesIndexed() async {
    await assertRewrites(
      r'''
void f(List<String> names, List<int> ages) {
  for (var i = 0; i < names.length; i++) {
    print('${names[i]} ${ages[i]} $i');
  }
}
''',
      header: 'final (i, name) in names.indexed',
      fixed: r'''
void f(List<String> names, List<int> ages) {
  for (final (i, name) in names.indexed) {
    print('$name ${ages[i]} $i');
  }
}
''',
    );
  }

  Future<void> test_interpolationKeepsBracesOnlyBeforeLettersOrDigits() async {
    await assertRewrites(
      r'''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    print('${xs[i]}px ${xs[i]}$i ${xs[i]}.');
  }
}
''',
      header: 'final (i, x) in xs.indexed',
      fixed: r'''
void f(List<int> xs) {
  for (final (i, x) in xs.indexed) {
    print('${x}px $x$i $x.');
  }
}
''',
    );
  }

  Future<void> test_everyReadIsReplaced() async {
    await assertRewrites(
      '''
int f(List<int> xs) {
  var sum = 0;
  for (var i = 0; i < xs.length; i++) {
    sum += xs[i] * xs[i];
  }
  return sum;
}
''',
      header: 'final x in xs',
      fixed: '''
int f(List<int> xs) {
  var sum = 0;
  for (final x in xs) {
    sum += x * x;
  }
  return sum;
}
''',
    );
  }

  Future<void> test_listLiteralElement() async {
    await assertRewrites(
      '''
List<int> f(List<int> candidates, List<int> refs) => [
  for (var i = 0; i < candidates.length; i++) candidates[i] + refs[i],
];
''',
      header: 'final (i, candidate) in candidates.indexed',
      fixed: '''
List<int> f(List<int> candidates, List<int> refs) => [
  for (final (i, candidate) in candidates.indexed) candidate + refs[i],
];
''',
    );
  }

  Future<void> test_mapLiteralElementWithIf() async {
    await assertRewrites(
      '''
Map<int, String> f(List<String> keys, int bits) => {
  for (var bit = 0; bit < keys.length; bit++)
    if ((bits >> bit) & 1 == 1) bit: keys[bit],
};
''',
      header: 'final (bit, key) in keys.indexed',
      fixed: '''
Map<int, String> f(List<String> keys, int bits) => {
  for (final (bit, key) in keys.indexed)
    if ((bits >> bit) & 1 == 1) bit: key,
};
''',
    );
  }

  Future<void> test_prefixIncrementAndTypedIndex() async {
    await assertRewrites(
      '''
void f(List<int> xs) {
  for (int i = 0; i < xs.length; ++i) {
    print(xs[i]);
  }
}
''',
      header: 'final x in xs',
      fixed: '''
void f(List<int> xs) {
  for (final x in xs) {
    print(x);
  }
}
''',
    );
  }

  Future<void> test_compoundIncrement() async {
    await assertRewrites(
      '''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i += 1) {
    print(xs[i]);
  }
}
''',
      header: 'final x in xs',
      fixed: '''
void f(List<int> xs) {
  for (final x in xs) {
    print(x);
  }
}
''',
    );
  }

  Future<void> test_listReadThroughChainOfNames() async {
    await assertRewrites(
      '''
class Legend {
  final List<String> tokenModifiers = [];
}

void f(Legend legend) {
  for (var i = 0; i < legend.tokenModifiers.length; i++) {
    print(legend.tokenModifiers[i]);
  }
}
''',
      header: 'final tokenModifier in legend.tokenModifiers',
      fixed: '''
class Legend {
  final List<String> tokenModifiers = [];
}

void f(Legend legend) {
  for (final tokenModifier in legend.tokenModifiers) {
    print(tokenModifier);
  }
}
''',
    );
  }

  Future<void> test_listReadThroughThis() async {
    await assertRewrites(
      '''
class Box {
  final List<int> entries = [];

  void f() {
    for (var i = 0; i < this.entries.length; i++) {
      print(this.entries[i]);
    }
  }
}
''',
      header: 'final entry in this.entries',
      fixed: '''
class Box {
  final List<int> entries = [];

  void f() {
    for (final entry in this.entries) {
      print(entry);
    }
  }
}
''',
    );
  }

  Future<void> test_elementOfPluralWithEsIsSingular() async {
    await assertRewrites(
      '''
void f(List<int> statuses) {
  for (var i = 0; i < statuses.length; i++) {
    print(statuses[i]);
  }
}
''',
      header: 'final status in statuses',
      fixed: '''
void f(List<int> statuses) {
  for (final status in statuses) {
    print(status);
  }
}
''',
    );
  }

  Future<void> test_elementOfReservedSingularIsElement() async {
    await assertRewrites(
      '''
void f(List<int> classes) {
  for (var i = 0; i < classes.length; i++) {
    print(classes[i]);
  }
}
''',
      header: 'final element in classes',
      fixed: '''
void f(List<int> classes) {
  for (final element in classes) {
    print(element);
  }
}
''',
    );
  }

  Future<void> test_elementOfSingularNameIsElement() async {
    await assertRewrites(
      '''
void f(List<int> data) {
  for (var i = 0; i < data.length; i++) {
    print(data[i]);
  }
}
''',
      header: 'final element in data',
      fixed: '''
void f(List<int> data) {
  for (final element in data) {
    print(element);
  }
}
''',
    );
  }

  Future<void> test_elementNameThatLoopUsesGetsNumber() async {
    await assertRewrites(
      '''
void f(List<int> xs, int x) {
  for (var i = 0; i < xs.length; i++) {
    print(xs[i] + x);
  }
}
''',
      header: 'final x2 in xs',
      fixed: '''
void f(List<int> xs, int x) {
  for (final x2 in xs) {
    print(x2 + x);
  }
}
''',
    );
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

/// The end of the header of the `for` loop at [start] in [code], after the
/// `)` that closes its `(`.
int _headerEnd(String code, int start) {
  var depth = 0;
  for (final (offset, char) in code.split('').indexed.skip(start)) {
    if (char == '(') {
      depth++;
    } else if (char == ')' && --depth == 0) {
      return offset + 1;
    }
  }
  throw ArgumentError('No header at $start.');
}
