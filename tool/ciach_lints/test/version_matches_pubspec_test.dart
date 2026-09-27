/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/version_matches_pubspec.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(VersionMatchesPubspecTest);
  });
}

@reflectiveTest
class VersionMatchesPubspecTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = VersionMatchesPubspec();
    super.setUp();
    newPubspecYamlFile(testPackageRootPath, '''
name: test
version: 1.2.3
''');
  }

  Future<void> test_matching() async {
    await assertNoDiagnostics('''
const ciachVersion = '1.2.3';
''');
  }

  Future<void> test_mismatched() async {
    await assertDiagnostics(
      '''
const ciachVersion = '1.2.4';
''',
      [
        lint(21, 7, messageContainsAll: ["'1.2.4'", "'1.2.3'"]),
      ],
    );
  }

  Future<void> test_otherConstant() async {
    await assertNoDiagnostics('''
const otherVersion = '1.2.4';
''');
  }
}
