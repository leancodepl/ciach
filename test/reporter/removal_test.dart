import 'package:ciach/src/reporter.dart';
import 'package:test/test.dart';

void main() {
  group('Reporter.removal', () {
    test('says what was removed, left and deleted, with the hints it took', () {
      final text = Reporter.removal(
        const .new(
          filesChanged: 2,
          deletedFiles: [(filePath: 'lib/empty.dart', unlinkedFrom: [])],
        ),
        removed: 3,
        blocked: 1,
        notes: ['Foo._: prefer `abstract final class`'],
      );
      expect(
        text,
        'Removed 3 unused declarations from 2 files. 1 left in place — unsafe '
        'to auto-remove. Deleted 1 now-empty file: lib/empty.dart. '
        "Run 'dart format' to tidy up spacing.\n"
        'Note: Foo._: prefer `abstract final class`',
      );
    });

    test('says so when the user declined', () {
      expect(Reporter.removal(null), 'Skipped removal.');
    });
  });
}
