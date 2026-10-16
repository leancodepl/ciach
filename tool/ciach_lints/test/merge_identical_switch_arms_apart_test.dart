/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/switch_arms.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(MergeIdenticalSwitchArmsApartTest);
  });
}

/// Arms with the same body that other arms separate.
@reflectiveTest
class MergeIdenticalSwitchArmsApartTest() extends SwitchArmsTest {
  Future<void> test_armApartJoinsTheFirstArm() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  2 => 1,
  _ => 3,
};
''',
      '2 => 1',
      advice: "'0 || 2'",
      fixed: '''
int f(int n) => switch (n) {
  0 || 2 => 1,
  1 => 2,
  _ => 3,
};
''',
    );
  }

  Future<void> test_armsNextToTheFirstArmAndApartFromItJoinIt() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 1,
  2 => 2,
  3 => 1,
  _ => 3,
};
''',
      '1 => 1',
      advice: "'0 || 1 || 3'",
      fixed: '''
int f(int n) => switch (n) {
  0 || 1 || 3 => 1,
  2 => 2,
  _ => 3,
};
''',
    );
  }

  Future<void> test_armApartMovesPastTheArmsOfItsGroup() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  > 5 => 1,
  1 => 2,
  2 => 1,
  _ => 3,
};
''',
      '> 5 => 1',
      advice: "'0 || > 5 || 2'",
      fixed: '''
int f(int n) => switch (n) {
  0 || > 5 || 2 => 1,
  1 => 2,
  _ => 3,
};
''',
    );
  }

  Future<void> test_lastArmApartJoinsTheFirstArm() async {
    await assertMerges(
      '''
enum Kind { a, b, c }

int f(Kind k) => switch (k) {
  .a => 1,
  .b => 2,
  .c => 1,
};
''',
      '.c => 1',
      advice: "'.a || .c'",
      fixed: '''
enum Kind { a, b, c }

int f(Kind k) => switch (k) {
  .a || .c => 1,
  .b => 2,
};
''',
    );
  }

  Future<void> test_twoGroupsApart() async {
    const code = '''
enum Kind { a, b, c, d }

int f(Kind k) => switch (k) {
  .a => 1,
  .b => 2,
  .c => 1,
  .d => 2,
};
''';
    await assertDiagnostics(code, [
      lint(code.indexOf('.c => 1'), 7, correctionContains: "'.a || .c'"),
      lint(code.indexOf('.d => 2'), 7, correctionContains: "'.b || .d'"),
    ]);
    await assertFixes(code, '''
enum Kind { a, b, c, d }

int f(Kind k) => switch (k) {
  .a || .c => 1,
  .b || .d => 2,
};
''');
  }

  Future<void> test_statementCaseApart() async {
    await assertMerges(
      '''
void f(int n) {
  switch (n) {
    case 0:
      print('a');
    case 1:
      print('b');
    case 2:
      print('a');
    default:
      print('c');
  }
}
''',
      "case 2:\n      print('a');",
      advice: "'0 || 2'",
      fixed: '''
void f(int n) {
  switch (n) {
    case 0 || 2:
      print('a');
    case 1:
      print('b');
    default:
      print('c');
  }
}
''',
    );
  }

  Future<void> test_negativeNumbersAndDoublesApart() async {
    await assertMerges(
      '''
String f(num n) => switch (n) {
  1 => 'a',
  0.5 => 'b',
  -1 => 'a',
  _ => 'c',
};
''',
      "-1 => 'a'",
      advice: "'1 || -1'",
      fixed: '''
String f(num n) => switch (n) {
  1 || -1 => 'a',
  0.5 => 'b',
  _ => 'c',
};
''',
    );
  }

  Future<void> test_stringsBoolsAndNullApart() async {
    await assertMerges(
      '''
int f(Object? o) => switch (o) {
  'a' => 1,
  true => 2,
  null => 3,
  'b' => 1,
  _ => 4,
};
''',
      "'b' => 1",
      advice: "''a' || 'b''",
      fixed: '''
int f(Object? o) => switch (o) {
  'a' || 'b' => 1,
  true => 2,
  null => 3,
  _ => 4,
};
''',
    );
  }

  Future<void> test_namedConstantsApart() async {
    await assertMerges(
      '''
const one = 1;
const half = 0.5;
const name = 'n';
const yes = true;
const nothing = null;

class Limits {
  static const three = 3;
}

String f(Object? o) {
  const two = 2;
  return switch (o) {
    0 => 'a',
    one => 'b',
    two => 'c',
    half => 'd',
    name => 'e',
    yes => 'f',
    nothing => 'g',
    Limits.three => 'a',
    _ => 'h',
  };
}
''',
      "Limits.three => 'a'",
      advice: "'0 || Limits.three'",
      fixed: '''
const one = 1;
const half = 0.5;
const name = 'n';
const yes = true;
const nothing = null;

class Limits {
  static const three = 3;
}

String f(Object? o) {
  const two = 2;
  return switch (o) {
    0 || Limits.three => 'a',
    one => 'b',
    two => 'c',
    half => 'd',
    name => 'e',
    yes => 'f',
    nothing => 'g',
    _ => 'h',
  };
}
''',
    );
  }

  Future<void> test_enumValuesApart() async {
    await assertMerges(
      '''
enum Kind { a, b, c, d }

const first = Kind.a;

int f(Kind k) => switch (k) {
  .d => 1,
  first => 2,
  Kind.b => 3,
  .c => 1,
};
''',
      '.c => 1',
      advice: "'.d || .c'",
      fixed: '''
enum Kind { a, b, c, d }

const first = Kind.a;

int f(Kind k) => switch (k) {
  .d || .c => 1,
  first => 2,
  Kind.b => 3,
};
''',
    );
  }

  Future<void> test_enumValuesWithAnImportPrefixApart() async {
    newFile('$testPackageLibPath/kind.dart', 'enum Kind { a, b, c }\n');
    await assertMerges(
      '''
import 'kind.dart' as k;

int f(k.Kind kind) => switch (kind) {
  k.Kind.a => 1,
  k.Kind.b => 2,
  k.Kind.c => 1,
};
''',
      'k.Kind.c => 1',
      advice: "'k.Kind.a || k.Kind.c'",
      fixed: '''
import 'kind.dart' as k;

int f(k.Kind kind) => switch (kind) {
  k.Kind.a || k.Kind.c => 1,
  k.Kind.b => 2,
};
''',
    );
  }

  Future<void> test_armApartPastAnArmWithSeveralValues() async {
    await assertMerges(
      '''
String f(int n) => switch (n) {
  0 => 'a',
  2 || (4) => 'b',
  3 => 'a',
  _ => 'c',
};
''',
      "3 => 'a'",
      advice: "'0 || 3'",
      fixed: '''
String f(int n) => switch (n) {
  0 || 3 => 'a',
  2 || (4) => 'b',
  _ => 'c',
};
''',
    );
  }

  Future<void> test_armInAGroupJoinsNoOtherGroup() async {
    // `6 || 7 => 1` can't move past `5 || 6 => 2`, so `8 => 1` joins `0 => 1`
    // and not `6 || 7 => 1` as well.
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  4 => 1,
  5 || 6 => 2,
  6 || 7 => 1,
  8 => 1,
  _ => 3,
};
''',
      '4 => 1',
      advice: "'0 || 4 || 8'",
      fixed: '''
int f(int n) => switch (n) {
  0 || 4 || 8 => 1,
  5 || 6 => 2,
  6 || 7 => 1,
  _ => 3,
};
''',
    );
  }

  Future<void> test_armApartPastAGuardedArmStays() async {
    await assertNoDiagnostics('''
String f(int n) => switch (n) {
  0 => 'a',
  final v when v.isEven => 'b',
  2 => 'a',
  _ => 'c',
};
''');
  }

  Future<void> test_armApartPastAnEqualDoubleStays() async {
    await assertNoDiagnostics('''
String f(num n) => switch (n) {
  0 => 'a',
  1.0 => 'b',
  1 => 'a',
  _ => 'c',
};
''');
  }

  Future<void> test_armApartPastNegativeZeroStays() async {
    await assertNoDiagnostics('''
String f(num n) => switch (n) {
  1 => 'a',
  -0.0 => 'b',
  0 => 'a',
  _ => 'c',
};
''');
  }

  Future<void> test_armApartPastAnObjectConstantStays() async {
    // A class can override `==`, so `origin` may equal `1`.
    await assertNoDiagnostics('''
class Point {
  const Point(this.x, this.y);
  final int x;
  final int y;
}

const origin = Point(0, 0);

String f(Object o) => switch (o) {
  0 => 'a',
  origin => 'b',
  1 => 'a',
  _ => 'c',
};
''');
  }

  Future<void> test_emptyCasesApartStay() async {
    // Each empty case falls into the body after it.
    await assertNoDiagnostics('''
void f(int n) {
  switch (n) {
    case 0:
    case 1:
      print('a');
    case 2:
    case 3:
      print('b');
    default:
      print('c');
  }
}
''');
  }

  Future<void> test_armApartAfterAnEmptyCaseStays() async {
    // `case 2:` falls into the body of `case 3:`, so that body stays.
    await assertNoDiagnostics('''
void f(int n) {
  switch (n) {
    case 0:
      print('a');
    case 1:
      print('b');
    case 2:
    case 3:
      print('a');
    default:
      print('c');
  }
}
''');
  }
}
