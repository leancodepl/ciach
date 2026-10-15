/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/avoid_empty_collection_fallback.dart';
import 'package:test/test.dart';

import 'fixes.dart';

/// Runs `avoid_empty_collection_fallback` and its fix on the code of a test.
abstract class EmptyFallbackTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = AvoidEmptyCollectionFallback();
    super.setUp();
  }

  /// Checks that [flagged] in [code] is flagged with [advice] in the
  /// correction, and that the fix turns [code] into [fixed], which compiles
  /// with no warning, or offers nothing when [fixed] is `null`.
  Future<void> assertFallback(
    String code,
    String flagged, {
    required String advice,
    required String? fixed,
  }) async {
    await assertDiagnostics(code, [
      lint(code.indexOf(flagged), flagged.length, correctionContains: advice),
    ]);
    expect(
      await applyFixes(
        code,
        AvoidEmptyCollectionFallback.code,
        SkipNullCollection.new,
      ),
      fixed,
    );
    if (fixed != null) {
      final file = newFile('$testPackageLibPath/fixed.dart', fixed);
      expect((await resolveFile(file.path)).diagnostics, isEmpty);
    }
  }
}
