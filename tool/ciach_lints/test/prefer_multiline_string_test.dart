/*
 * AI-Provenance:
 *   harness: Claude Code
 */

// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_multiline_string.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferMultilineStringTest);
    defineReflectiveTests(ConvertToMultilineStringTest);
  });
}

@reflectiveTest
class PreferMultilineStringTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferMultilineString();
    super.setUp();
  }

  Future<void> test_noNewlines() async {
    await assertNoDiagnostics('''
const s = 'plain';
''');
  }

  Future<void> test_finalNewlineOnly() async {
    await assertNoDiagnostics(r'''
const s = 'line\n';
''');
  }

  Future<void> test_oneInteriorNewline() async {
    await assertNoDiagnostics(r'''
const s = 'a\nb';
''');
  }

  Future<void> test_oneInteriorNewlineThenFinal() async {
    await assertNoDiagnostics(r'''
const s = '\n\n';
''');
  }

  Future<void> test_oneInteriorNewlineBetweenInterpolations() async {
    await assertNoDiagnostics(r'''
String f(Object result, int stdout, int stderr) => '$stdout\n$stderr';
''');
  }

  Future<void> test_twoInteriorNewlines() async {
    await assertDiagnostics(
      r'''
const s = 'a\nb\nc';
''',
      [
        lint(10, 9, messageContainsAll: ['2 interior']),
      ],
    );
  }

  Future<void> test_twoInteriorNewlinesThenFinal() async {
    await assertDiagnostics(
      r'''
const s = 'a\nb\nc\n';
''',
      [
        lint(10, 11, messageContainsAll: ['2 interior']),
      ],
    );
  }

  Future<void> test_doubleQuoted() async {
    await assertDiagnostics(
      r'''
const s = "a\nb\nc";
''',
      [lint(10, 9)],
    );
  }

  Future<void> test_interpolated() async {
    await assertDiagnostics(
      r'''
String f(int x) => 'a\n$x\n${x + 1}';
''',
      [
        lint(19, 17, messageContainsAll: ['2 interior']),
      ],
    );
  }

  Future<void> test_interpolatedNewlinesCountedAcrossParts() async {
    await assertNoDiagnostics(r'''
String f(int x) => 'a\n$x\n';
''');
  }

  Future<void> test_escapedBackslash() async {
    await assertNoDiagnostics(r'''
const s = 'a\\nb\\nc';
''');
  }

  Future<void> test_rawString() async {
    await assertNoDiagnostics(r'''
const s = r'a\nb\nc';
''');
  }

  Future<void> test_multilineString() async {
    await assertNoDiagnostics(r"""
const s = '''
a\nb\nc''';
""");
  }
}

@reflectiveTest
class ConvertToMultilineStringTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferMultilineString();
    super.setUp();
  }

  Future<void> test_plain() async {
    await assertFix(
      r'''
const s = 'a\nb\nc';
''',
      """
const s = '''
a
b
c''';
""",
    );
  }

  Future<void> test_interpolated() async {
    await assertFix(
      r'''
String f(int x) => 'a\n$x\n${x + 1}\nb';
''',
      r"""
String f(int x) => '''
a
$x
${x + 1}
b''';
""",
    );
  }

  Future<void> test_quotes() async {
    await assertFix(
      r'''
const s = 'it\'s\n"quoted"\nend';
''',
      """
const s = '''
it's
"quoted"
end''';
""",
    );
  }

  Future<void> test_otherEscapesKept() async {
    await assertFix(
      r'''
const s = 'tab\t\n\$x\\n\nend';
''',
      r"""
const s = '''
tab\t
\$x\\n
end''';
""",
    );
  }

  Future<void> test_endsWithNewline() async {
    await assertFix(
      r'''
const s = 'a\nb\nc\n';
''',
      """
const s = '''
a
b
c
''';
""",
    );
  }

  Future<void> test_startsWithNewline() async {
    await assertFix(
      r'''
const s = '\na\nb';
''',
      """
const s = '''

a
b''';
""",
    );
  }

  Future<void> test_tripleSingleQuotesInside() async {
    await assertFix(
      r"""
const s = "a\n'''\nb";
""",
      '''
const s = """
a
\'\'\'
b""";
''',
    );
  }

  Future<void> test_endsWithSingleQuote() async {
    await assertFix(
      r'''
const s = 'a\nb\nc\'';
''',
      '''
const s = """
a
b
c'""";
''',
    );
  }

  Future<void> test_trailingWhitespace() async {
    await assertNoFix(r'''
const s = 'a \nb\nc';
''');
  }

  Future<void> test_bothTripleQuotesInside() async {
    await assertNoFix(r'''
const s = 'a\n\'\'\'\n"""';
''');
  }

  /// Asserts that the fix rewrites [code], which the rule flags once, into
  /// [expected].
  Future<void> assertFix(String code, String expected) async {
    expect(await _applyFix(code), expected);
  }

  /// Asserts that the fix is not offered for [code], which the rule flags
  /// once.
  Future<void> assertNoFix(String code) async {
    expect(await _applyFix(code), isNull);
  }

  Future<String?> _applyFix(String code) async {
    final file = newFile(testFile.path, code);
    final unit = await resolveFile(file.path);
    final library = await unit.session.getResolvedLibrary(
      file.path,
    ) as ResolvedLibraryResult;
    final diagnostic = unit.diagnostics.singleWhere(
      (diagnostic) => diagnostic.diagnosticCode == PreferMultilineString.code,
    );
    final producer = ConvertToMultilineString(
      context: CorrectionProducerContext.createResolved(
        libraryResult: library,
        unitResult: unit,
        diagnostic: diagnostic,
        selectionOffset: diagnostic.offset,
        selectionLength: diagnostic.length,
      ),
    );
    final builder = ChangeBuilder(session: unit.session);
    await producer.compute(builder);
    final edits = builder.sourceChange.getFileEdit(file.path)?.edits;
    return edits == null ? null : SourceEdit.applySequence(code, edits);
  }
}
