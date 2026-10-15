/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_none_and_where_not.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferNoneAndWhereNotTest);
  });
}

const _import = "import 'package:collection/collection.dart';\n\n";

/// Declarations that the snippets of the tests use. The analyzer's mock SDK
/// has no `Iterable.any` or `Iterable.every`, so an extension stands in for
/// them.
const _helpers = '''
bool odd(int x) => x.isOdd;
final seen = <int>{};

extension<T> on Iterable<T> {
  bool any(bool Function(T element) test) => where(test).isNotEmpty;
  bool every(bool Function(T element) test) => !any((e) => !test(e));
}
''';

@reflectiveTest
class PreferNoneAndWhereNotTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferNoneAndWhereNot();
    super.setUp();
    newPackage('collection').addFile('lib/collection.dart', '''
extension IterableExtension<T> on Iterable<T> {
  bool none(bool Function(T element) test) => !any(test);
  Iterable<T> whereNot(bool Function(T element) test) =>
      where((element) => !test(element));
}
''');
    writeTestPackageConfig2();
  }

  /// Checks that [flagged] in [snippet], after [_helpers] and, when
  /// [imported], the `package:collection` import, is flagged with [replacement]
  /// as the suggestion, and that the fix replaces it, adding the import when
  /// [replacement] needs it.
  Future<void> assertReplaces(
    String snippet,
    String flagged,
    String replacement, {
    bool imported = false,
  }) async {
    final head = '${imported ? _import : ''}$_helpers';
    final code = '$head$snippet';
    await assertDiagnostics(code, [
      lint(
        code.indexOf(flagged),
        flagged.length,
        messageContainsAll: ["'$replacement'"],
      ),
    ]);
    final needsImport =
        replacement.contains('none(') || replacement.contains('whereNot(');
    expect(
      await applyFixes(code, PreferNoneAndWhereNot.code, RemoveNegation.new),
      '${needsImport || imported ? _import : ''}$_helpers'
      '${snippet.replaceFirst(flagged, replacement)}',
    );
  }

  Future<void> assertKeeps(String snippet) =>
      assertNoDiagnostics('$_helpers$snippet');

  Future<void> test_negatedAny() async {
    await assertReplaces(
      'bool f(List<int> xs) => !xs.any((x) => x > 0);\n',
      '!xs.any((x) => x > 0)',
      'xs.none((x) => x > 0)',
    );
  }

  Future<void> test_negatedAnyWithImport() async {
    await assertReplaces(
      '''
bool f(List<int> xs) => !xs.any(odd);
bool g(List<int> xs) => xs.none(odd);
''',
      '!xs.any(odd)',
      'xs.none(odd)',
      imported: true,
    );
  }

  Future<void> test_negatedNone() async {
    await assertReplaces(
      'bool f(List<int> xs) => !xs.none(odd);\n',
      '!xs.none(odd)',
      'xs.any(odd)',
      imported: true,
    );
  }

  Future<void> test_negatedAnyInParentheses() async {
    await assertReplaces(
      'bool f(List<int> xs) => !(xs.any(odd));\n',
      '!(xs.any(odd))',
      'xs.none(odd)',
    );
  }

  Future<void> test_whereWithNegatedTearOff() async {
    await assertReplaces(
      'Iterable<int> f(List<int> xs) => xs.where((x) => !seen.contains(x));\n',
      'xs.where((x) => !seen.contains(x))',
      'xs.whereNot(seen.contains)',
    );
  }

  Future<void> test_whereWithNegatedProperty() async {
    await assertReplaces(
      'Iterable<int> f(List<int> xs) => xs.where((x) => !x.isEven);\n',
      'xs.where((x) => !x.isEven)',
      'xs.whereNot((x) => x.isEven)',
    );
  }

  Future<void> test_whereWithNegatedCallOnComputedReceiver() async {
    await assertReplaces(
      '''
Set<int> make() => {};
Iterable<int> f(List<int> xs) => xs.where((x) => !make().contains(x));
''',
      'xs.where((x) => !make().contains(x))',
      'xs.whereNot((x) => make().contains(x))',
    );
  }

  Future<void> test_whereNotWithNegatedPredicate() async {
    await assertReplaces(
      'Iterable<int> f(List<int> xs) => xs.whereNot((x) => !odd(x));\n',
      'xs.whereNot((x) => !odd(x))',
      'xs.where(odd)',
      imported: true,
    );
  }

  Future<void> test_anyWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => xs.any((x) => !seen.contains(x));\n',
      'xs.any((x) => !seen.contains(x))',
      '!xs.every(seen.contains)',
    );
  }

  Future<void> test_everyWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => xs.every((x) => !odd(x));\n',
      'xs.every((x) => !odd(x))',
      'xs.none(odd)',
    );
  }

  Future<void> test_noneWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => xs.none((x) => !odd(x));\n',
      'xs.none((x) => !odd(x))',
      'xs.every(odd)',
      imported: true,
    );
  }

  Future<void> test_negatedAnyWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => !xs.any((x) => !odd(x));\n',
      '!xs.any((x) => !odd(x))',
      'xs.every(odd)',
    );
  }

  Future<void> test_negatedEveryWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => !xs.every((x) => !odd(x));\n',
      '!xs.every((x) => !odd(x))',
      'xs.any(odd)',
    );
  }

  Future<void> test_negatedNoneWithNegatedPredicate() async {
    await assertReplaces(
      'bool f(List<int> xs) => !xs.none((x) => !odd(x));\n',
      '!xs.none((x) => !odd(x))',
      '!xs.every(odd)',
      imported: true,
    );
  }

  Future<void> test_newNegationBeforeAccessIsParenthesized() async {
    await assertReplaces(
      'String f(List<int> xs) => xs.any((x) => !odd(x)).toString();\n',
      'xs.any((x) => !odd(x))',
      '(!xs.every(odd))',
    );
  }

  Future<void> test_nullAwareCall() async {
    await assertReplaces(
      'Iterable<int>? f(List<int>? xs) => xs?.where((x) => !odd(x));\n',
      'xs?.where((x) => !odd(x))',
      'xs?.whereNot(odd)',
    );
  }

  Future<void> test_negatedEvery() async {
    await assertKeeps('bool f(List<int> xs) => !xs.every(odd);\n');
  }

  Future<void> test_whereWithoutNegation() async {
    await assertKeeps('Iterable<int> f(List<int> xs) => xs.where(odd);\n');
  }

  Future<void> test_negationInsidePredicate() async {
    await assertKeeps(
      'Iterable<int> f(List<int> xs) => xs.where((x) => !odd(x) && x > 0);\n',
    );
  }

  Future<void> test_otherReceiver() async {
    await assertKeeps('''
class Checks {
  bool any(bool Function(int) test) => test(0);
}

bool f(Checks c) => !c.any(odd);
''');
  }
}
