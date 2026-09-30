import 'package:ciach/src/plural.dart';
import 'package:test/test.dart';

void main() {
  test('uses the singular only for exactly one', () {
    expect(plural(0, 'file', 'files'), '0 files');
    expect(plural(1, 'file', 'files'), '1 file');
    expect(plural(2, 'entry', 'entries'), '2 entries');
  });

  test('picks the word alone', () {
    expect(pluralWord(1, 'is', 'are'), 'is');
    expect(pluralWord(2, 'is', 'are'), 'are');
  });
}
