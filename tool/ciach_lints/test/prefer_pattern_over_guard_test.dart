/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/pattern_over_guard.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferPatternOverGuardTest);
  });
}

@reflectiveTest
class PreferPatternOverGuardTest() extends PatternOverGuardTest {
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
      replacement: 'final count && > 0',
      fixed: '''
void f(int n) {
  if (n case final count && > 0) print(count);
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

  Future<void> test_comparisonOfUnreadTypedVariableKeepsTheType() async {
    await assertMoves(
      '''
void f(Object o) {
  if (o case final int v when v > 0) print('positive');
}
''',
      'when v > 0',
      replacement: 'int() && > 0',
      fixed: '''
void f(Object o) {
  if (o case int() && > 0) print('positive');
}
''',
    );
  }

  Future<void> test_comparisonOfUnreadVariableOfTheMatchedType() async {
    await assertMoves(
      '''
void f(int n) {
  if (n case final int v when v > 0) print('positive');
}
''',
      'when v > 0',
      replacement: '> 0',
      fixed: '''
void f(int n) {
  if (n case > 0) print('positive');
}
''',
    );
  }

  Future<void> test_comparisonOfPositionalRecordField() async {
    await assertMoves(
      '''
void f((int, int) pair) {
  if (pair case (final a, final b) when a > 0) print(b);
}
''',
      'when a > 0',
      replacement: '(> 0, final b)',
      fixed: '''
void f((int, int) pair) {
  if (pair case (> 0, final b)) print(b);
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
      replacement: 'final count && != -1',
      fixed: '''
void f(int n) {
  if (n case final count && != -1) print(count);
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
      replacement: 'final v as int && > 0',
      fixed: '''
void f(Object o) {
  if (o case final v as int && > 0) print(v);
}
''',
    );
  }

  Future<void> test_comparisonOfReadNullCheckedVariable() async {
    await assertMoves(
      '''
const unknown = '';

String? f(String? s) => switch (s) {
  final path? when path != unknown => path,
  _ => null,
};
''',
      'when path != unknown',
      replacement: 'final path? && != unknown',
      fixed: '''
const unknown = '';

String? f(String? s) => switch (s) {
  final path? && != unknown => path,
  _ => null,
};
''',
    );
  }

  Future<void> test_comparisonOfUnreadNullCheckedVariable() async {
    await assertMoves(
      '''
void f(int? n) {
  if (n case final v? when v > 0) print('positive');
}
''',
      'when v > 0',
      replacement: '(> 0)?',
      fixed: '''
void f(int? n) {
  if (n case (> 0)?) print('positive');
}
''',
    );
  }

  Future<void> test_comparisonOfReadNullCheckedField() async {
    await assertMoves(
      '''
void f(Token t) {
  if (t case Token(:final text?) when text != 'x') print(text);
}
''',
      "when text != 'x'",
      replacement: "Token(text: final text? && != 'x')",
      fixed: '''
void f(Token t) {
  if (t case Token(text: final text? && != 'x')) print(text);
}
''',
    );
  }

  Future<void> test_comparisonOfUnreadNullCheckedField() async {
    await assertMoves(
      '''
void f(Token t) {
  if (t case Token(:final text?) when text != 'x') print('not x');
}
''',
      "when text != 'x'",
      replacement: "Token(text: (!= 'x')?)",
      fixed: '''
void f(Token t) {
  if (t case Token(text: (!= 'x')?)) print('not x');
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
