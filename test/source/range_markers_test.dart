import 'package:ciach/src/source/range_markers.dart';
import 'package:test/test.dart';

void main() {
  /// The line and markers of each empty range in [content].
  List<(int, String, String)> rangesIn(String content) => [
    for (final (:line, :open, :close, spans: _) in emptyRanges(content))
      (line, open, close),
  ];

  test('finds each kind of range with nothing between its comments', () {
    expect(
      rangesIn('''
// coverage:ignore-start
// coverage:ignore-end
// ciach:ignore-start
// A note.
// ciach:ignore-end
// dart format off

// dart format on
/* cSpell:disable */
// cSpell:disable
// cSpell:enable
'''),
      [
        (1, 'coverage:ignore-start', 'coverage:ignore-end'),
        (3, 'ciach:ignore-start', 'ciach:ignore-end'),
        (6, 'dart format off', 'dart format on'),
        (10, 'cspell:disable', 'cspell:enable'),
      ],
    );
  });

  test('skips a range with code in it', () {
    expect(
      rangesIn('''
// coverage:ignore-start
void f() {}
// coverage:ignore-end
'''),
      isEmpty,
    );
  });

  test('pairs nested ranges inside out', () {
    expect(
      rangesIn('''
// coverage:ignore-start
void f() {}
// coverage:ignore-start
// coverage:ignore-end
// coverage:ignore-end
'''),
      [(3, 'coverage:ignore-start', 'coverage:ignore-end')],
    );
  });

  test('does not take cspell:disable-next-line for an opening comment', () {
    expect(
      rangesIn('''
// cspell:disable-next-line
// cspell:enable
'''),
      isEmpty,
    );
  });

  test('spans a comment after code from the blanks before it', () {
    const content = '''
void f() {} // dart format off
// dart format on
''';
    final [(:spans, line: _, open: _, close: _)] = emptyRanges(content);
    expect(
      [for (final (:start, :end) in spans) content.substring(start, end)],
      [' // dart format off', '// dart format on\n'],
    );
  });
}
