/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_single_string_literal.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferSingleStringLiteralTest);
  });
}

@reflectiveTest
class PreferSingleStringLiteralTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferSingleStringLiteral();
    super.setUp();
  }

  /// Checks that the adjacent strings starting at [flagged] in [code] are
  /// flagged with [joined] as the suggestion, and that the fix turns [code]
  /// into [fixed].
  Future<void> assertJoins(
    String code,
    String flagged, {
    required String joined,
    required String fixed,
  }) async {
    await assertDiagnostics(code, [
      lint(code.indexOf(flagged), flagged.length, correctionContains: joined),
    ]);
    expect(
      await applyFixes(
        code,
        PreferSingleStringLiteral.code,
        JoinAdjacentStrings.new,
      ),
      fixed,
    );
  }

  Future<void> test_twoLines() async {
    await assertJoins(
      '''
const s =
    'first half, '
    'second half';
''',
      "'first half, '\n    'second half'",
      joined: "'first half, second half'",
      fixed: '''
const s =
    'first half, second half';
''',
    );
  }

  Future<void> test_oneLine() async {
    await assertJoins(
      '''
const s = 'a' 'b';
''',
      "'a' 'b'",
      joined: "'ab'",
      fixed: '''
const s = 'ab';
''',
    );
  }

  Future<void> test_threeStrings() async {
    await assertJoins(
      '''
const s = 'a' 'b' 'c';
''',
      "'a' 'b' 'c'",
      joined: "'abc'",
      fixed: '''
const s = 'abc';
''',
    );
  }

  Future<void> test_joinedLineAt120Columns() async {
    final head = 'a' * 50;
    final tail = 'b' * 57;
    // `const s = '` is 11 columns, the text 107 and `';` 2: 120 in all.
    await assertJoins(
      '''
const s = '$head'
    '$tail';
''',
      "'$head'\n    '$tail'",
      joined: "'$head$tail'",
      fixed:
          '''
const s = '$head$tail';
''',
    );
  }

  Future<void> test_joinedLinePast120Columns() async {
    final head = 'a' * 50;
    final tail = 'b' * 58;
    await assertNoDiagnostics('''
const s = '$head'
    '$tail';
''');
  }

  Future<void> test_textAfterTheStringsCounts() async {
    final head = 'a' * 50;
    final tail = 'b' * 53;
    await assertNoDiagnostics('''
void f(String s, int i) {}
void g() => f('$head'
    '$tail', 1);
''');
  }

  Future<void> test_commentBetweenStrings() async {
    await assertNoDiagnostics('''
const s =
    'a' // Why the string is split.
    'b';
''');
  }

  Future<void> test_multilineString() async {
    await assertNoDiagnostics("""
const s = '''
a''' 'b';
""");
  }

  Future<void> test_escapesKept() async {
    await assertJoins(
      r'''
const s = 'a\n' 'b\t\u{1F600}';
''',
      r"'a\n' 'b\t\u{1F600}'",
      joined: r"'a\nb\t\u{1F600}'",
      fixed: r'''
const s = 'a\nb\t\u{1F600}';
''',
    );
  }

  Future<void> test_rawStrings() async {
    await assertJoins(
      r'''
const s = r'\d+' r'$';
''',
      r"r'\d+' r'$'",
      joined: r"r'\d+$'",
      fixed: r'''
const s = r'\d+$';
''',
    );
  }

  Future<void> test_rawAndPlainString() async {
    await assertJoins(
      r'''
const s = r'\d+$' 'x';
''',
      r"r'\d+$' 'x'",
      joined: r"'\\d+\$x'",
      fixed: r'''
const s = '\\d+\$x';
''',
    );
  }

  Future<void> test_doubleQuotedWithApostrophe() async {
    await assertJoins(
      '''
const s = "it's " 'fine';
''',
      '''"it's " 'fine\'''',
      joined: '''"it's fine"''',
      fixed: '''
const s = "it's fine";
''',
    );
  }

  Future<void> test_bothQuotes() async {
    const code = '''
const s = "it's " '"fine"';
''';
    await assertJoins(
      code,
      code.substring(code.indexOf('"'), code.indexOf(';')),
      joined: r"""'it\'s "fine"'""",
      fixed: r'''
const s = 'it\'s "fine"';
''',
    );
  }

  Future<void> test_doubleQuotesWithoutApostrophe() async {
    await assertJoins(
      '''
const s = "a" "b";
''',
      '"a" "b"',
      joined: "'ab'",
      fixed: '''
const s = 'ab';
''',
    );
  }

  Future<void> test_interpolationBeforeIdentifierCharacter() async {
    await assertJoins(
      r'''
String f(int a) => '$a' 'bc';
''',
      r"'$a' 'bc'",
      joined: r"'${a}bc'",
      fixed: r'''
String f(int a) => '${a}bc';
''',
    );
  }

  Future<void> test_interpolationBeforeOtherCharacter() async {
    await assertJoins(
      r'''
String f(int a) => '$a' '.b';
''',
      r"'$a' '.b'",
      joined: r"'$a.b'",
      fixed: r'''
String f(int a) => '$a.b';
''',
    );
  }

  Future<void> test_bracedInterpolation() async {
    await assertJoins(
      r'''
String f(int a) => '${a + 1}' 'b';
''',
      r"'${a + 1}' 'b'",
      joined: r"'${a + 1}b'",
      fixed: r'''
String f(int a) => '${a + 1}b';
''',
    );
  }

  Future<void> test_escapedDollar() async {
    await assertJoins(
      r'''
const s = '\$x' 'y';
''',
      r"'\$x' 'y'",
      joined: r"'\$xy'",
      fixed: r'''
const s = '\$xy';
''',
    );
  }

  Future<void> test_singleString() async {
    await assertNoDiagnostics('''
const s = 'ab';
''');
  }
}
