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
    defineReflectiveTests(MergeIdenticalSwitchArmsCatchAllTest);
  });
}

/// Arms with the same body as `_` or `default`, which match every value.
@reflectiveTest
class MergeIdenticalSwitchArmsCatchAllTest() extends SwitchArmsTest {
  Future<void> test_runThatEndsWithWildcard() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  2 => 2,
  _ => 2,
};
''',
      '2 => 2',
      advice: 'removing the arms that the last arm covers',
      fixed: '''
int f(int n) => switch (n) {
  0 => 1,
  _ => 2,
};
''',
    );
  }

  Future<void> test_statementCaseBeforeDefault() async {
    await assertMerges(
      '''
void f(int n) {
  switch (n) {
    case 0:
      print('zero');
    case 1:
      print('other');
    default:
      print('other');
  }
}
''',
      "default:\n      print('other');",
      advice: 'removing the arms that the last arm covers',
      fixed: '''
void f(int n) {
  switch (n) {
    case 0:
      print('zero');
    default:
      print('other');
  }
}
''',
    );
  }

  Future<void> test_statementCasesAfterAnEmptyCaseBeforeDefault() async {
    // `case 1:` falls into `default:` once `case 2:` and `case 3:` are
    // removed.
    await assertMerges(
      '''
void f(int n) {
  switch (n) {
    case 0:
      print('a');
    case 1:
    case 2:
      print('b');
    case 3:
      print('b');
    default:
      print('b');
  }
}
''',
      "case 3:\n      print('b');",
      advice: 'removing the arms that the last arm covers',
      fixed: '''
void f(int n) {
  switch (n) {
    case 0:
      print('a');
    case 1:
    default:
      print('b');
  }
}
''',
    );
  }

  Future<void> test_firstArmApartThatTheCatchAllCovers() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  _ => 1,
};
''',
      '_ => 1',
      advice: 'removing the arms that the last arm covers',
      fixed: '''
int f(int n) => switch (n) {
  1 => 2,
  _ => 1,
};
''',
    );
  }

  Future<void> test_armApartPastAnArmThatTheCatchAllCovers() async {
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  > 5 => 1,
  _ => 1,
};
''',
      '> 5 => 1',
      advice: 'removing the arms that the last arm covers',
      fixed: '''
int f(int n) => switch (n) {
  1 => 2,
  _ => 1,
};
''',
    );
  }

  Future<void> test_firstStatementCaseApartThatDefaultCovers() async {
    await assertMerges(
      '''
void f(int n) {
  switch (n) {
    case 0:
      print('a');
    case 1:
      print('b');
    default:
      print('a');
  }
}
''',
      "default:\n      print('a');",
      advice: 'removing the arms that the last arm covers',
      fixed: '''
void f(int n) {
  switch (n) {
    case 1:
      print('b');
    default:
      print('a');
  }
}
''',
    );
  }

  Future<void> test_catchAllAndArmsApartInOneSwitch() async {
    const code = '''
int f(int n) => switch (n) {
  0 => 1,
  1 => 2,
  2 => 3,
  3 => 2,
  _ => 3,
};
''';
    await assertDiagnostics(code, [
      lint(code.indexOf('3 => 2'), 6, correctionContains: "'1 || 3'"),
      lint(
        code.indexOf('_ => 3'),
        6,
        correctionContains: 'removing the arms that the last arm covers',
      ),
    ]);
    await assertFixes(code, '''
int f(int n) => switch (n) {
  0 => 1,
  1 || 3 => 2,
  _ => 3,
};
''');
  }

  Future<void> test_armThatTheCatchAllCoversJoinsNoOtherArm() async {
    // `5 => 1` can't move past `5 || 6 => 2`, so it stays.
    await assertMerges(
      '''
int f(int n) => switch (n) {
  0 => 1,
  5 => 1,
  5 || 6 => 2,
  _ => 1,
};
''',
      '_ => 1',
      advice: 'removing the arms that the last arm covers',
      fixed: '''
int f(int n) => switch (n) {
  5 => 1,
  5 || 6 => 2,
  _ => 1,
};
''',
    );
  }

  Future<void> test_armApartPastAGuardedArmBeforeTheCatchAllStays() async {
    await assertNoDiagnostics('''
int f(int n) => switch (n) {
  0 => 1,
  final v when v.isEven => 2,
  _ => 1,
};
''');
  }
}
