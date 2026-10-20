/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_let.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferLetWithoutExtensionTest);
  });
}

/// A package that can't import ciach's `lib/src/util/extensions.dart`.
@reflectiveTest
class PreferLetWithoutExtensionTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferLet();
    super.setUp();
  }

  Future<void> test_onlyTheNullAwareChainIsReported() async {
    const chain = 's == null ? null : s.length';
    const code =
        '''
int? f(String? s) => $chain;
int? g(String? s) => s != null ? int.parse(s) : null;
''';
    await assertDiagnostics(code, [
      lint(
        code.indexOf(chain),
        chain.length,
        correctionContains: "'s?.length'",
      ),
    ]);
  }
}
