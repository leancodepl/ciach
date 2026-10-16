// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer/src/diagnostic/diagnostic.dart' as diag;
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/prefer_let.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'support/fixes.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(PreferLetTest);
  });
}

const _import = "import 'package:ciach/src/util/extensions.dart';\n\n";

@reflectiveTest
class PreferLetTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = PreferLet();
    super.setUp();
    newPackage('ciach').addFile('lib/src/util/extensions.dart', '''
extension Let<T extends Object> on T {
  R let<R>(R Function(T it) transform) => transform(this);
}
''');
    writeTestPackageConfig2();
  }

  /// Checks that [code] gets one `prefer_let` diagnostic per snippet in
  /// [flagged], in order of appearance, each spanning the snippet or, for one
  /// starting with `switch`, the whole switch up to its closing brace, and
  /// each suggesting the matching entry of [sketches] when given; and that
  /// applying every offered [ReplaceWithLet] yields [fixed].
  Future<void> assertRewrites(
    String code,
    List<String> flagged, {
    List<String> sketches = const [],
    required String fixed,
  }) async {
    final spans = <(int, int)>[];
    var from = 0;
    for (final snippet in flagged) {
      final start = code.indexOf(snippet, from);
      final end = snippet.startsWith('switch')
          ? code.indexOf('\n}', start) + 2
          : start + snippet.length;
      spans.add((start, end));
      from = end;
    }
    final quoted = [for (final sketch in sketches) "'$sketch'"];
    await assertDiagnostics(code, [
      for (final (i, (start, end)) in spans.indexed)
        lint(
          start,
          end - start,
          correctionContains: i < quoted.length ? quoted[i] : null,
        ),
    ]);
    expect(await applyFixes(code, PreferLet.code, ReplaceWithLet.new), fixed);
  }

  Future<void> test_switchToChain() async {
    await assertRewrites(
      '''
class Box {
  Box? inner;
  int size = 0;
}
int? f(Box? b) => switch (b) {
  final v? => v.inner!.size,
  null => null,
};
List<int>? g(List<List<int>>? l) => switch (l) {
  final v? => v[0],
  null => null,
};
Box? h(Box? b) => switch (b) {
  final v? => v,
  null => null,
};
''',
      ['switch (b)', 'switch (l)', 'switch (b)'],
      sketches: ['b?.inner!.size', 'l?[0]', 'b'],
      fixed: '''
class Box {
  Box? inner;
  int size = 0;
}
int? f(Box? b) => b?.inner!.size;
List<int>? g(List<List<int>>? l) => l?[0];
Box? h(Box? b) => b;
''',
    );
  }

  Future<void> test_switchToTearOff() async {
    await assertRewrites(
      '''
int? f(String? s) => switch (s) {
  final v? => int.parse(v),
  null => null,
};
''',
      ['switch (s)'],
      sketches: ['s?.let(int.parse)'],
      fixed:
          '''
${_import}int? f(String? s) => s?.let(int.parse);
''',
    );
  }

  Future<void> test_switchToLambda() async {
    await assertRewrites(
      '''
int? f(String? s) => switch (s) {
  final v? => v.length + 1,
  null => null,
};
''',
      ['switch (s)'],
      sketches: ['s?.let((v) => …)'],
      fixed:
          '''
${_import}int? f(String? s) => s?.let((v) => v.length + 1);
''',
    );
  }

  Future<void> test_nullArmFirst() async {
    await assertRewrites(
      '''
int? f(String? s) => switch (s) {
  null => null,
  final v => int.parse(v, radix: 16),
};
''',
      ['switch (s)'],
      fixed:
          '''
${_import}int? f(String? s) => s?.let((v) => int.parse(v, radix: 16));
''',
    );
  }

  Future<void> test_wildcardArmLast() async {
    await assertRewrites(
      '''
int? f(String? s) => switch (s) {
  final v? => v.length + 2,
  _ => null,
};
''',
      ['switch (s)'],
      fixed:
          '''
${_import}int? f(String? s) => s?.let((v) => v.length + 2);
''',
    );
  }

  Future<void> test_typedVariable() async {
    await assertRewrites(
      '''
int? f(String? s) => switch (s) {
  final String v? => v.length + 1,
  null => null,
};
int? g(String? s) => switch (s) {
  final String v => v.length + 1,
  _ => null,
};
''',
      ['switch (s)', 'switch (s)'],
      fixed:
          '''
${_import}int? f(String? s) => s?.let((String v) => v.length + 1);
int? g(String? s) => s?.let((String v) => v.length + 1);
''',
    );
  }

  Future<void> test_lowPrecedenceTarget() async {
    await assertRewrites(
      '''
int? f(String? a, String? b) => switch (a ?? b) {
  final v? => v.length + 1,
  null => null,
};
''',
      ['switch (a ?? b)'],
      fixed:
          '''
${_import}int? f(String? a, String? b) => (a ?? b)?.let((v) => v.length + 1);
''',
    );
  }

  Future<void> test_existingImport() async {
    await assertRewrites(
      '''
${_import}int g(String s) => s.let((v) => v.length + 1);

int? f(String? s) => switch (s) {
  final v? => v.length + 1,
  null => null,
};
''',
      ['switch (s)'],
      fixed:
          '''
${_import}int g(String s) => s.let((v) => v.length + 1);

int? f(String? s) => s?.let((v) => v.length + 1);
''',
    );
  }

  Future<void> test_conditional() async {
    await assertRewrites(
      '''
int? f(String? s) => s == null ? null : s.length;
int? g(String? s) => s != null ? int.parse(s) : null;
int h(String? s) => s == null ? 0 : s.length + 1;
int i(String? s) => null != s ? s.length : s.hashCode;
''',
      [
        's == null ? null : s.length',
        's != null ? int.parse(s) : null',
        's == null ? 0 : s.length + 1',
        'null != s ? s.length : s.hashCode',
      ],
      sketches: [
        's?.length',
        's?.let(int.parse)',
        's?.let((s) => …) ?? …',
        's?.length ?? …',
      ],
      fixed:
          '''
${_import}int? f(String? s) => s?.length;
int? g(String? s) => s?.let(int.parse);
int h(String? s) => s?.let((s) => s.length + 1) ?? 0;
int i(String? s) => s?.length ?? s.hashCode;
''',
    );
  }

  Future<void> test_conditionalFallbackNeedsParentheses() async {
    await assertRewrites(
      '''
int f(String? s, bool b) => s == null ? (b ? 1 : 2) : s.length;
''',
      ['s == null ? (b ? 1 : 2) : s.length'],
      fixed: '''
int f(String? s, bool b) => s?.length ?? (b ? 1 : 2);
''',
    );
  }

  Future<void> test_conditionalNotUsingTheVariable() async {
    await assertNoDiagnostics('''
int f(String? s, String t) => s == null ? 0 : t.length;
bool g(String? s) => s == null ? false : true;
''');
  }

  Future<void> test_conditionalOnField() async {
    await assertRewrites(
      '''
class C {
  String? s;
  int? f() => s == null ? null : s!.length;
  int g() => s != null ? int.parse(s!) : 0;
}
int h(C c) => c.s != null ? c.s!.length + 1 : -1;
int i(C c, int s) => c.s == null ? 0 : c.s!.length + s;
''',
      [
        's == null ? null : s!.length',
        's != null ? int.parse(s!) : 0',
        'c.s != null ? c.s!.length + 1 : -1',
        'c.s == null ? 0 : c.s!.length + s',
      ],
      sketches: [
        's?.length',
        's?.let(int.parse) ?? …',
        'c.s?.let((s) => …) ?? …',
        'c.s?.let((it) => …) ?? …',
      ],
      fixed:
          '''
${_import}class C {
  String? s;
  int? f() => s?.length;
  int g() => s?.let(int.parse) ?? 0;
}
int h(C c) => c.s?.let((s) => s.length + 1) ?? -1;
int i(C c, int s) => c.s?.let((it) => it.length + s) ?? 0;
''',
    );
  }

  Future<void> test_conditionalOnPrivateField() async {
    await assertRewrites(
      '''
class C {
  String? _s;
  int f() => _s == null ? 0 : _s!.length + 1;
}
int g(C c) => c._s != null ? c._s!.length + 1 : -1;
''',
      [
        '_s == null ? 0 : _s!.length + 1',
        'c._s != null ? c._s!.length + 1 : -1',
      ],
      sketches: ['_s?.let((s) => …) ?? …', 'c._s?.let((s) => …) ?? …'],
      fixed:
          '''
${_import}class C {
  String? _s;
  int f() => _s?.let((s) => s.length + 1) ?? 0;
}
int g(C c) => c._s?.let((s) => s.length + 1) ?? -1;
''',
    );
  }

  Future<void> test_conditionalOnFieldNamedOnlyWithUnderscores() async {
    await assertRewrites(
      '''
class C {
  String? __;
}
int f(C c) => c.__ != null ? c.__!.length + 1 : -1;
''',
      ['c.__ != null ? c.__!.length + 1 : -1'],
      sketches: ['c.__?.let((it) => …) ?? …'],
      fixed:
          '''
${_import}class C {
  String? __;
}
int f(C c) => c.__?.let((it) => it.length + 1) ?? -1;
''',
    );
  }

  Future<void> test_conditionalOnPrivateFieldClashingWithAParameter() async {
    await assertRewrites(
      '''
class C {
  String? _s;
}
int f(C c, int s) => c._s == null ? 0 : c._s!.length + s;
''',
      ['c._s == null ? 0 : c._s!.length + s'],
      sketches: ['c._s?.let((it) => …) ?? …'],
      fixed:
          '''
${_import}class C {
  String? _s;
}
int f(C c, int s) => c._s?.let((it) => it.length + s) ?? 0;
''',
    );
  }

  Future<void> test_conditionalOnFieldUsedBare() async {
    await assertRewrites(
      '''
class C {
  String? s;
  int f() => s == null ? 0 : s.hashCode;
  String? g() => s != null ? s : null;
  int h() => s != null ? s!.length + s.hashCode : 0;
}
''',
      [
        's == null ? 0 : s.hashCode',
        's != null ? s : null',
        's != null ? s!.length + s.hashCode : 0',
      ],
      sketches: ['s?.hashCode ?? …', 's', 's?.let((s) => …) ?? …'],
      fixed:
          '''
${_import}class C {
  String? s;
  int f() => s?.hashCode ?? 0;
  String? g() => s;
  int h() => s?.let((s) => s.length + s.hashCode) ?? 0;
}
''',
    );
  }

  Future<void> test_conditionalAssigningTheField() async {
    await assertNoDiagnostics('''
class C {
  int? n;
  int f() => n == null ? 0 : n = n! + 1;
}
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

  Future<void> test_switchWithFallback() async {
    await assertRewrites(
      '''
int f(String? s) => switch (s) {
  final v? => v.length,
  null => 0,
};
int g(String? s) => switch (s) {
  final v? => v.length + 1,
  _ => 0,
};
''',
      ['switch (s)', 'switch (s)'],
      sketches: ['s?.length ?? …', 's?.let((v) => …) ?? …'],
      fixed:
          '''
${_import}int f(String? s) => s?.length ?? 0;
int g(String? s) => s?.let((v) => v.length + 1) ?? 0;
''',
    );
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

  Future<void> test_typePatternNarrows() async {
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
