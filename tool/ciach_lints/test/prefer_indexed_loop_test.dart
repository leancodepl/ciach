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
      header: 'final element in xs',
      fixed: '''
void f(List<int> xs) {
  for (final element in xs) {
    print(element);
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
      header: 'final (i, element) in names.indexed',
      fixed: r'''
void f(List<String> names, List<int> ages) {
  for (final (i, element) in names.indexed) {
    print('$element ${ages[i]} $i');
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
      header: 'final (i, element) in xs.indexed',
      fixed: r'''
void f(List<int> xs) {
  for (final (i, element) in xs.indexed) {
    print('${element}px $element$i $element.');
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
      header: 'final element in xs',
      fixed: '''
int f(List<int> xs) {
  var sum = 0;
  for (final element in xs) {
    sum += element * element;
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
      header: 'final (i, element) in candidates.indexed',
      fixed: '''
List<int> f(List<int> candidates, List<int> refs) => [
  for (final (i, element) in candidates.indexed) element + refs[i],
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
      header: 'final (bit, element) in keys.indexed',
      fixed: '''
Map<int, String> f(List<String> keys, int bits) => {
  for (final (bit, element) in keys.indexed)
    if ((bits >> bit) & 1 == 1) bit: element,
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
      header: 'final element in xs',
      fixed: '''
void f(List<int> xs) {
  for (final element in xs) {
    print(element);
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
      header: 'final element in xs',
      fixed: '''
void f(List<int> xs) {
  for (final element in xs) {
    print(element);
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
      header: 'final element in legend.tokenModifiers',
      fixed: '''
class Legend {
  final List<String> tokenModifiers = [];
}

void f(Legend legend) {
  for (final element in legend.tokenModifiers) {
    print(element);
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
      header: 'final element in this.entries',
      fixed: '''
class Box {
  final List<int> entries = [];

  void f() {
    for (final element in this.entries) {
      print(element);
    }
  }
}
''',
    );
  }

  Future<void> test_elementNameThatLoopUsesGetsNumber() async {
    await assertRewrites(
      '''
void f(List<int> xs, int element, int element2) {
  for (var i = 0; i < xs.length; i++) {
    print(xs[i] + element + element2);
  }
}
''',
      header: 'final element3 in xs',
      fixed: '''
void f(List<int> xs, int element, int element2) {
  for (final element3 in xs) {
    print(element3 + element + element2);
  }
}
''',
    );
  }

  Future<void> test_finalDeclarationOfElementGivesItsName() async {
    await assertRewrites(
      '''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    print(i);
    final value = xs[i];
    print(value + xs[i]);
  }
}
''',
      header: 'final (i, value) in xs.indexed',
      fixed: '''
void f(List<int> xs) {
  for (final (i, value) in xs.indexed) {
    print(i);
    print(value + value);
  }
}
''',
    );
  }

  Future<void> test_typedOrVarDeclarationOfElementKeepsItsStatement() async {
    await assertRewrites(
      '''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    final num typed = xs[i];
    var changed = xs[i];
    changed++;
    print([typed, changed]);
  }
}
''',
      header: 'final element in xs',
      fixed: '''
void f(List<int> xs) {
  for (final element in xs) {
    final num typed = element;
    var changed = element;
    changed++;
    print([typed, changed]);
  }
}
''',
    );
  }

  Future<void> test_newNameIsOneLinkedEditGroup() async {
    const code = r'''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    print('${xs[i]} ${xs[i] + 1}');
  }
}
''';
    final [change] = await fixChanges(
      '$code$_indexed',
      PreferIndexedLoop.code,
      LoopOverElements.new,
    );
    final [group] = change.linkedEditGroups;
    const fixed = r'''
void f(List<int> xs) {
  for (final element in xs) {
    print('$element ${element + 1}');
  }
}
''';
    expect(
      [for (final position in group.positions) position.offset],
      [
        fixed.indexOf('element in'),
        fixed.indexOf(r'$element') + 1,
        fixed.indexOf('element +'),
      ],
    );
    expect(group.length, 'element'.length);
  }

  Future<void> test_reusedNameIsNoLinkedEditGroup() async {
    final [change] = await fixChanges(
      '''
void f(List<int> xs) {
  for (var i = 0; i < xs.length; i++) {
    final value = xs[i];
    print(value);
  }
}
$_indexed''',
      PreferIndexedLoop.code,
      LoopOverElements.new,
    );
    expect(change.linkedEditGroups, isEmpty);
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
