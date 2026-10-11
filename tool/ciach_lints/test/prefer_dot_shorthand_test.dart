// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analysis_server_plugin/edit/fix/dart_fix_context.dart';
import 'package:analysis_server_plugin/src/correction/dart_change_workspace.dart';
import 'package:analysis_server_plugin/src/correction/fix_generators.dart';
import 'package:analysis_server_plugin/src/correction/fix_processor.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:analyzer_testing/src/test_instrumentation_service.dart';
import 'package:ciach_lints/src/prefer_dot_shorthand.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferDotShorthandTest);
  });
}

const _style = '''
enum Style { plain, bold }
''';

@reflectiveTest
class PreferDotShorthandTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferDotShorthand();
    super.setUp();
    registeredFixGenerators.registerFixForLint(
      PreferDotShorthand.code,
      ReplaceWithDotShorthand.new,
    );
  }

  @override
  Future<void> tearDown() async {
    registeredFixGenerators.lintProducers.remove(PreferDotShorthand.code);
    await super.tearDown();
  }

  /// Checks that [code] gets one `prefer_dot_shorthand` diagnostic per
  /// snippet in [flagged], in order of appearance, and that applying every
  /// offered [ReplaceWithDotShorthand] yields [fixed].
  Future<void> assertShorthands(
    String code,
    List<String> flagged, {
    required String fixed,
  }) async {
    var from = 0;
    await assertDiagnostics(code, [
      for (final snippet in flagged)
        lint(from = code.indexOf(snippet, from), snippet.length),
    ]);
    final library = await result.session.getResolvedLibrary(
      testFile.path,
    ) as ResolvedLibraryResult;
    final edits = <SourceEdit>[];
    for (final diagnostic in result.diagnostics) {
      if (diagnostic.diagnosticCode != PreferDotShorthand.code) {
        continue;
      }
      final fixes = await computeFixes(
        DartFixContext(
          instrumentationService: TestInstrumentationService(),
          workspace: DartChangeWorkspace([await session]),
          libraryResult: library,
          unitResult: result,
          error: diagnostic,
        ),
      );
      final fix = fixes.singleWhere(
        (f) => f.kind == ReplaceWithDotShorthand.kind,
      );
      edits.addAll(fix.change.getFileEdit(testFile.path)!.edits);
    }
    // Later edits first, so earlier offsets stay valid as the text shrinks.
    edits.sort((a, b) => b.offset.compareTo(a.offset));
    expect(SourceEdit.applySequence(result.content, edits), fixed);
  }

  Future<void> test_argument() async {
    await assertShorthands(
      '''
${_style}void use(Style style) {}
void f() => use(Style.plain);
''',
      ['Style.plain'],
      fixed:
          '''
${_style}void use(Style style) {}
void f() => use(.plain);
''',
    );
  }

  Future<void> test_namedArgument() async {
    await assertShorthands(
      '''
${_style}void use({required Style style}) {}
void f() => use(style: Style.plain);
''',
      ['Style.plain'],
      fixed:
          '''
${_style}void use({required Style style}) {}
void f() => use(style: .plain);
''',
    );
  }

  Future<void> test_typedVariable() async {
    await assertShorthands(
      '''
${_style}void f() {
  Style style = Style.plain;
  style = Style.bold;
}
''',
      ['Style.plain', 'Style.bold'],
      fixed:
          '''
${_style}void f() {
  Style style = .plain;
  style = .bold;
}
''',
    );
  }

  Future<void> test_returns() async {
    await assertShorthands(
      '''
${_style}Style f() => Style.plain;
Style g() {
  return Style.bold;
}
Style? h() => Style.plain;
Future<Style> i() async => Style.bold;
''',
      ['Style.plain', 'Style.bold', 'Style.plain', 'Style.bold'],
      fixed:
          '''
${_style}Style f() => .plain;
Style g() {
  return .bold;
}
Style? h() => .plain;
Future<Style> i() async => .bold;
''',
    );
  }

  Future<void> test_equality() async {
    await assertShorthands(
      '''
${_style}bool f(Style style) => style == Style.plain || style != Style.bold;
''',
      ['Style.plain', 'Style.bold'],
      fixed:
          '''
${_style}bool f(Style style) => style == .plain || style != .bold;
''',
    );
  }

  Future<void> test_branches() async {
    await assertShorthands(
      '''
${_style}Style f(bool b, Style? s) => b ? Style.plain : (s ?? Style.bold);
Style g(bool b) => switch (b) {
  true => Style.plain,
  false => Style.bold,
};
''',
      ['Style.plain', 'Style.bold', 'Style.plain', 'Style.bold'],
      fixed:
          '''
${_style}Style f(bool b, Style? s) => b ? .plain : (s ?? .bold);
Style g(bool b) => switch (b) {
  true => .plain,
  false => .bold,
};
''',
    );
  }

  Future<void> test_constantPattern() async {
    await assertShorthands(
      '''
${_style}bool f(Style style) => switch (style) {
  Style.plain => true,
  _ => false,
};
bool g(Style style) {
  if (style case Style.bold) {
    return true;
  }
  return false;
}
''',
      ['Style.plain', 'Style.bold'],
      fixed:
          '''
${_style}bool f(Style style) => switch (style) {
  .plain => true,
  _ => false,
};
bool g(Style style) {
  if (style case .bold) {
    return true;
  }
  return false;
}
''',
    );
  }

  Future<void> test_collections() async {
    await assertShorthands(
      '''
${_style}List<Style> f() => [Style.plain, if (true) Style.bold];
Set<Style> g() => <Style>{Style.plain};
Map<Style, int> h() => {Style.bold: 1};
void i(List<Style> styles) => styles.add(Style.plain);
''',
      ['Style.plain', 'Style.bold', 'Style.plain', 'Style.bold', 'Style.plain'],
      fixed:
          '''
${_style}List<Style> f() => [.plain, if (true) .bold];
Set<Style> g() => <Style>{.plain};
Map<Style, int> h() => {.bold: 1};
void i(List<Style> styles) => styles.add(.plain);
''',
    );
  }

  Future<void> test_defaultValue() async {
    await assertShorthands(
      '''
${_style}void f({Style style = Style.plain}) {}
''',
      ['Style.plain'],
      fixed:
          '''
${_style}void f({Style style = .plain}) {}
''',
    );
  }

  Future<void> test_constructors() async {
    await assertShorthands(
      '''
class Key {
  const Key(this.a);
  const Key.named(this.a);
  final int a;
}
Key f() => Key(1);
Key g() => Key.named(2);
Key h() => const Key(3);
''',
      ['Key(1)', 'Key.named(2)', 'const Key(3)'],
      fixed: '''
class Key {
  const Key(this.a);
  const Key.named(this.a);
  final int a;
}
Key f() => .new(1);
Key g() => .named(2);
Key h() => const .new(3);
''',
    );
  }

  Future<void> test_staticMethod() async {
    await assertShorthands(
      '''
int f() => int.parse('1');
List<int> g() => List.filled(1, 0);
''',
      ["int.parse('1')", 'List.filled(1, 0)'],
      fixed: '''
int f() => .parse('1');
List<int> g() => .filled(1, 0);
''',
    );
  }

  Future<void> test_importPrefix() async {
    await assertShorthands(
      '''
import 'dart:core' as core;

core.Duration f() => core.Duration.zero;
core.Duration g() => core.Duration(days: 1);
''',
      ['core.Duration.zero', 'core.Duration(days: 1)'],
      fixed: '''
import 'dart:core' as core;

core.Duration f() => .zero;
core.Duration g() => .new(days: 1);
''',
    );
  }

  Future<void> test_noContext() async {
    await assertNoDiagnostics('''
${_style}final a = Style.plain;
final b = () => Style.plain;
int c() => Style.plain.index;
String d() => '\${Style.plain}';
final e = [Style.plain];
''');
  }

  Future<void> test_otherContext() async {
    await assertNoDiagnostics('''
${_style}class Colors {
  static const red = 1;
}
Object a() => Style.plain;
int b() => Colors.red;
List<int> c() => List<int>.filled(1, 0);
Style d() => .plain;
''');
  }

  Future<void> test_annotation() async {
    await assertNoDiagnostics('''
class Timeout {
  const Timeout(Duration duration);
}
@Timeout(Duration(minutes: 1))
void f() {}
''');
  }

  Future<void> test_inferredTypeParameter() async {
    await assertNoDiagnostics('''
${_style}T same<T>(T value) => value;
Style f() => same(Style.plain);
''');
  }
}
