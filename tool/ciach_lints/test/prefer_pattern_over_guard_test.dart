/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_pattern_over_guard.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferPatternOverGuardTest);
  });
}

/// Declarations that the snippets of the tests match on.
const _types = '''
enum Kind { a, b }

class Token {
  Token(this.kind, this.flag, this.text);
  final Kind kind;
  final bool flag;
  final String? text;
}
''';

@reflectiveTest
class PreferPatternOverGuardTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferPatternOverGuard();
    super.setUp();
  }

  /// Checks that [snippet], after [_types], gets one diagnostic on the
  /// `when` clause [flagged], whose correction suggests [replacement], and
  /// that the fix turns it into [fixed].
  Future<void> assertMoves(
    String snippet,
    String flagged, {
    required String replacement,
    required String fixed,
  }) async {
    final code = '$_types\n$snippet';
    await assertDiagnostics(code, [
      lint(
        code.indexOf(flagged),
        flagged.length,
        correctionContains: "'$replacement'",
      ),
    ]);
    expect(
      await applyFixes(
        code,
        PreferPatternOverGuard.code,
        MoveGuardIntoPattern.new,
      ),
      '$_types\n$fixed',
    );
  }

  Future<void> assertKeeps(String snippet) =>
      assertNoDiagnostics('$_types\n$snippet');

  Future<void> test_typeTest() async {
    await assertMoves(
      r'''
String f(Object o) => switch (o) {
  final v when v is int => 'int $v',
  _ => 'other',
};
''',
      'when v is int',
      replacement: 'final int v',
      fixed: r'''
String f(Object o) => switch (o) {
  final int v => 'int $v',
  _ => 'other',
};
''',
    );
  }

  Future<void> test_typeTestOfVar() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case var v when v is String) print(v);
}
''',
      'when v is String',
      replacement: 'String v',
      fixed: '''
void f(Object o) {
  if (o case String v) print(v);
}
''',
    );
  }

  Future<void> test_typeTestReplacesType() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final num v when v is int) print(v);
}
''',
      'when v is int',
      replacement: 'final int v',
      fixed: '''
void f(Object o) {
  if (o case final int v) print(v);
}
''',
    );
  }

  Future<void> test_nullTest() async {
    await assertMoves(
      '''
void f(Map<String, int> m) {
  if (m['k'] case final v when v != null) print(v);
}
''',
      'when v != null',
      replacement: 'final v?',
      fixed: '''
void f(Map<String, int> m) {
  if (m['k'] case final v?) print(v);
}
''',
    );
  }

  Future<void> test_nullTestWithNullFirst() async {
    await assertMoves(
      '''
void f(Map<String, int> m) {
  if (m['k'] case final v when null != v) print(v);
}
''',
      'when null != v',
      replacement: 'final v?',
      fixed: '''
void f(Map<String, int> m) {
  if (m['k'] case final v?) print(v);
}
''',
    );
  }

  Future<void> test_nullTestOfShorthandField() async {
    await assertMoves(
      '''
void f(Token t) {
  if (t case Token(:final text) when text != null) print(text);
}
''',
      'when text != null',
      replacement: 'Token(:final text?)',
      fixed: '''
void f(Token t) {
  if (t case Token(:final text?)) print(text);
}
''',
    );
  }

  Future<void> test_comparisonOfReadVariable() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final count when count > 0) print(count);
}
''',
      'when count > 0',
      replacement: '> 0 && final count',
      fixed: '''
void f(int n) {
  if (n case > 0 && final count) print(count);
}
''',
    );
  }

  Future<void> test_comparisonOfUnreadVariable() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final count when count >= 2) print('many');
}
''',
      'when count >= 2',
      replacement: '>= 2',
      fixed: '''
void f(int n) {
  if (n case >= 2) print('many');
}
''',
    );
  }

  Future<void> test_comparisonWithConstantFirst() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final count when 0 < count) print('some');
}
''',
      'when 0 < count',
      replacement: '> 0',
      fixed: '''
void f(int n) {
  if (n case > 0) print('some');
}
''',
    );
  }

  Future<void> test_comparisonWithNegativeNumber() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final count when count != -1) print(count);
}
''',
      'when count != -1',
      replacement: '!= -1 && final count',
      fixed: '''
void f(int n) {
  if (n case != -1 && final count) print(count);
}
''',
    );
  }

  Future<void> test_comparisonOfShorthandField() async {
    await assertMoves(
      '''
const limit = 3;

void f(Token t) {
  if (t case Token(:final text) when text == 'x') print(limit);
}
''',
      "when text == 'x'",
      replacement: "Token(text: 'x')",
      fixed: '''
const limit = 3;

void f(Token t) {
  if (t case Token(text: 'x')) print(limit);
}
''',
    );
  }

  Future<void> test_equalityWithEnumValue() async {
    await assertMoves(
      '''
bool f(Token t) => switch (t) {
  Token(:final kind) when kind == .a => true,
  _ => false,
};
''',
      'when kind == .a',
      replacement: 'Token(kind: .a)',
      fixed: '''
bool f(Token t) => switch (t) {
  Token(kind: .a) => true,
  _ => false,
};
''',
    );
  }

  Future<void> test_equalityWithConstant() async {
    await assertMoves(
      '''
const limit = 3;

bool f(int n) => switch (n) {
  final v when v == limit => true,
  _ => false,
};
''',
      'when v == limit',
      replacement: 'limit',
      fixed: '''
const limit = 3;

bool f(int n) => switch (n) {
  limit => true,
  _ => false,
};
''',
    );
  }

  Future<void> test_boolVariable() async {
    await assertMoves(
      '''
int f(Token t) => switch (t) {
  Token(:final flag) when flag => 1,
  _ => 0,
};
''',
      'when flag',
      replacement: 'Token(flag: true)',
      fixed: '''
int f(Token t) => switch (t) {
  Token(flag: true) => 1,
  _ => 0,
};
''',
    );
  }

  Future<void> test_negatedBoolVariable() async {
    await assertMoves(
      '''
int f(Token t) => switch (t) {
  Token(:final flag) when !flag => 1,
  _ => 0,
};
''',
      'when !flag',
      replacement: 'Token(flag: false)',
      fixed: '''
int f(Token t) => switch (t) {
  Token(flag: false) => 1,
  _ => 0,
};
''',
    );
  }

  Future<void> test_testOfCastVariable() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v as int when v > 0) print(v);
}
''',
      'when v > 0',
      replacement: '(> 0 && final v) as int',
      fixed: '''
void f(Object o) {
  if (o case (> 0 && final v) as int) print(v);
}
''',
    );
  }

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

  Future<void> test_oneMovePerVariable() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final v when v is int && v > 0) print(v);
}
''',
      'when v is int && v > 0',
      replacement: 'final int v when v > 0',
      fixed: '''
void f(Object o) {
  if (o case final int v when v > 0) print(v);
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

  Future<void> test_memberTest() async {
    await assertKeeps('''
void f(List<int> xs) {
  if (xs case final v when v.isNotEmpty) print(v);
}
''');
  }

  Future<void> test_negatedTypeTest() async {
    await assertKeeps('''
void f(Object o) {
  if (o case final v when v is! int) print(v);
}
''');
  }

  Future<void> test_variableFromOutside() async {
    await assertKeeps('''
void f(Object o, Object other) {
  if (o case final v when other is int) print(v);
}
''');
  }

  Future<void> test_comparisonWithVariable() async {
    await assertKeeps('''
void f(int n, int limit) {
  if (n case final v when v > limit) print(v);
}
''');
  }

  Future<void> test_equalityOfReadVariable() async {
    await assertKeeps('''
String f(Token t) => switch (t) {
  Token(:final kind) when kind == Kind.a => kind.name,
  _ => '',
};
''');
  }

  Future<void> test_boolOfReadVariable() async {
    await assertKeeps('''
bool f(Token t) => switch (t) {
  Token(:final flag) when flag => flag,
  _ => false,
};
''');
  }
}
