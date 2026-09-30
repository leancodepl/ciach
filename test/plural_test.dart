import 'package:ciach/src/plural.dart';
import 'package:test/test.dart';

void main() {
  test('adds an s unless the count is 1', () {
    expect(plural(0, 'file'), '0 files');
    expect(plural(1, 'file'), '1 file');
    expect(plural(2, 'file'), '2 files');
  });

  test('takes an irregular plural', () {
    expect(plural(3, 'entry', 'entries'), '3 entries');
    expect(pluralWord(1, 'is', 'are'), 'is');
    expect(pluralWord(2, 'is', 'are'), 'are');
  });
}
