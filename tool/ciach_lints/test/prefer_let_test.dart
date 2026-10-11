// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/fix/dart_fix_context.dart';
import 'package:analysis_server_plugin/src/correction/dart_change_workspace.dart';
import 'package:analysis_server_plugin/src/correction/fix_generators.dart';
import 'package:analysis_server_plugin/src/correction/fix_processor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:analyzer_testing/src/test_instrumentation_service.dart';
import 'package:ciach_lints/src/prefer_let.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferLetTest);
  });
}

@reflectiveTest
class PreferLetTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferLet();
    super.setUp();
    newPackage('ciach').addFile('lib/src/extensions.dart', '''
extension Let<T extends Object> on T {
  R let<R>(R Function(T it) transform) => transform(this);
}
''');
    writeTestPackageConfig2();
    registeredFixGenerators.registerFixForLint(
      PreferLet.code,
      ReplaceWithLet.new,
    );
  }

  @override
  Future<void> tearDown() async {
    registeredFixGenerators.lintProducers.remove(PreferLet.code);
    await super.tearDown();
  }

  /// Checks that the single `prefer_let` diagnostic in the resolved test file
  /// offers [ReplaceWithLet], and that applying it yields [expected].
  Future<void> assertFix(String expected) async {
    final diagnostic = result.diagnostics.singleWhere(
      (d) => d.diagnosticCode == PreferLet.code,
    );
    final library = await result.session.getResolvedLibrary(
      testFile.path,
    ) as ResolvedLibraryResult;
    final fixes = await computeFixes(
      DartFixContext(
        instrumentationService: TestInstrumentationService(),
        workspace: DartChangeWorkspace([await session]),
        libraryResult: library,
        unitResult: result,
        error: diagnostic,
      ),
    );
    final fix = fixes.singleWhere((f) => f.kind == ReplaceWithLet.kind);
    final edits = fix.change.getFileEdit(testFile.path)!.edits;
    expect(SourceEdit.applySequence(result.content, edits), expected);
  }

  Future<void> test_nullArmLast() async {
    await assertDiagnostics(
      '''
int? f(String? s) => switch (s) {
  final v? => v.length,
  null => null,
};
''',
      [lint(21, 54)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int? f(String? s) => s?.let((v) => v.length);
''');
  }

  Future<void> test_nullArmFirst() async {
    await assertDiagnostics(
      '''
int? f(String? s) => switch (s) {
  null => null,
  final v => v.length,
};
''',
      [lint(21, 53)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int? f(String? s) => s?.let((v) => v.length);
''');
  }

  Future<void> test_wildcardArmLast() async {
    await assertDiagnostics(
      '''
int? f(String? s) => switch (s) {
  final v? => v.length,
  _ => null,
};
''',
      [lint(21, 51)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int? f(String? s) => s?.let((v) => v.length);
''');
  }

  Future<void> test_typedVariable() async {
    await assertDiagnostics(
      '''
int? f(String? o) => switch (o) {
  final String v? => v.length,
  null => null,
};
''',
      [lint(21, 61)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int? f(String? o) => o?.let((String v) => v.length);
''');
  }

  Future<void> test_lowPrecedenceTarget() async {
    await assertDiagnostics(
      '''
int? f(String? a, String? b) => switch (a ?? b) {
  final v? => v.length,
  null => null,
};
''',
      [lint(32, 59)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int? f(String? a, String? b) => (a ?? b)?.let((v) => v.length);
''');
  }

  Future<void> test_existingImport() async {
    await assertDiagnostics(
      '''
import 'package:ciach/src/extensions.dart';

int g(String s) => s.let((v) => v.length);

int? f(String? s) => switch (s) {
  final v? => v.length,
  null => null,
};
''',
      [lint(110, 54)],
    );
    await assertFix('''
import 'package:ciach/src/extensions.dart';

int g(String s) => s.let((v) => v.length);

int? f(String? s) => s?.let((v) => v.length);
''');
  }

  Future<void> test_wildcardArmFirst() async {
    // The value arm is unreachable, which the analyzer reports on its own.
    await assertDiagnostics(
      '''
int? f(String? s) => switch (s) {
  _ => null,
  final v? => v.length,
};
''',
      [error(diag.deadCode, 49, 20), error(diag.unreachableSwitchCase, 58, 2)],
    );
  }

  Future<void> test_nullMapsToValue() async {
    await assertNoDiagnostics('''
int f(String? s) => switch (s) {
  final v? => v.length,
  null => 0,
};
''');
  }

  Future<void> test_guard() async {
    await assertNoDiagnostics('''
int? f(String? s) => switch (s) {
  final v? when v.isNotEmpty => v.length,
  _ => null,
};
''');
  }

  Future<void> test_threeArms() async {
    await assertNoDiagnostics('''
int? f(Object? o) => switch (o) {
  final String v? => v.length,
  final int v? => v,
  _ => null,
};
''');
  }

  Future<void> test_typePattern() async {
    await assertNoDiagnostics('''
int? f(Object? o) => switch (o) {
  final String v => v.length,
  _ => null,
};
''');
  }

  Future<void> test_switchStatement() async {
    await assertNoDiagnostics('''
int? f(String? s) {
  int? length;
  switch (s) {
    case final v?:
      length = v.length;
    case null:
      length = null;
  }
  return length;
}
''');
  }
}
