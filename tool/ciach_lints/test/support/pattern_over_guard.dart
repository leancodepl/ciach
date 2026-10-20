/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_pattern_over_guard.dart';
import 'package:test/test.dart';

import 'fixes.dart';

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

/// Runs `prefer_pattern_over_guard` and its fix on snippets after [_types].
abstract class PatternOverGuardTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferPatternOverGuard();
    super.setUp();
  }

  /// Checks that [snippet], after [_types], gets one diagnostic on the
  /// `when` clause [flagged], whose correction suggests [replacement], and
  /// that the fix turns it into [fixed], which compiles and leaves nothing
  /// for the lint to flag.
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
    final file = newFile('$testPackageLibPath/fixed.dart', '$_types\n$fixed');
    expect((await resolveFile(file.path)).diagnostics, isEmpty);
  }

  Future<void> assertKeeps(String snippet) =>
      assertNoDiagnostics('$_types\n$snippet');
}
