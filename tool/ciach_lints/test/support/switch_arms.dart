/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/merge_identical_switch_arms.dart';
import 'package:test/test.dart';

import 'fixes.dart';

/// Runs `merge_identical_switch_arms` and its fix.
abstract class SwitchArmsTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = MergeIdenticalSwitchArms();
    super.setUp();
  }

  /// Checks that the arm [flagged] in [code] is flagged with [advice] in the
  /// correction, and that the fix turns [code] into [fixed].
  Future<void> assertMerges(
    String code,
    String flagged, {
    required String advice,
    required String fixed,
  }) async {
    await assertDiagnostics(code, [
      lint(code.indexOf(flagged), flagged.length, correctionContains: advice),
    ]);
    await assertFixes(code, fixed);
  }

  /// Checks that the fixes of every diagnostic in [code] turn it into
  /// [fixed], which compiles and leaves nothing for the lint to flag.
  Future<void> assertFixes(String code, String fixed) async {
    expect(
      await applyFixes(
        code,
        MergeIdenticalSwitchArms.code,
        MergeSwitchArms.new,
      ),
      fixed,
    );
    final file = newFile('$testPackageLibPath/fixed.dart', fixed);
    expect((await resolveFile(file.path)).diagnostics, isEmpty);
  }
}
