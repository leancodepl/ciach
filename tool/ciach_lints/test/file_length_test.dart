// test_reflective_loader discovers tests by their `test_` prefix.
// ignore_for_file: non_constant_identifier_names

import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';
import 'package:ciach_lints/src/file_length.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FileLengthTest);
  });

  group('lineCount', () {
    test('counts like wc -l, plus an unterminated last line', () {
      expect(lineCount(''), 0);
      expect(lineCount('a'), 1);
      expect(lineCount('a\n'), 1);
      expect(lineCount('a\nb'), 2);
      expect(lineCount('a\nb\n'), 2);
      expect(lineCount('\n\n'), 2);
    });
  });
}

@reflectiveTest
class FileLengthTest() extends AnalysisRuleTest {
  @override
  void setUp() {
    rule = FileLength();
    super.setUp();
  }

  /// A file of [lines] one-line declarations.
  static String fileOf(int lines) =>
      [for (var i = 0; i < lines; i++) 'void f$i() {}'].join('\n');

  Future<void> test_atTheLimit() async {
    await assertNoDiagnostics(fileOf(FileLength.maxLines));
  }

  Future<void> test_pastTheLimit() async {
    await assertDiagnostics(fileOf(FileLength.maxLines + 1), [
      lint(0, 0, messageContainsAll: ['501 lines', 'under 500']),
    ]);
  }

  Future<void> test_commentsCount() async {
    await assertDiagnostics(
      [for (var i = 0; i <= FileLength.maxLines; i++) '// $i'].join('\n'),
      [lint(0, 0)],
    );
  }
}
