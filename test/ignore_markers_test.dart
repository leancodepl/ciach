import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/ignore_markers.dart';
import 'package:test/test.dart';

void main() {
  /// The marker keeping a declaration that starts on [start] and is named on
  /// [nameLine], both one-based, as `marker@line`.
  String? keeping(String source, int start, [int? nameLine]) =>
      IgnoreMarkers.parse(source)
          .keeping(start: start - 1, nameLine: (nameLine ?? start) - 1)
          ?.let((kept) => '${kept.marker}@${kept.line + 1}');

  group('// ciach:ignore', () {
    test('on a line of its own keeps the declaration on the next line', () {
      const source = '''
// ciach:ignore
void kept() {}
void notKept() {}
''';
      expect(keeping(source, 2), 'ciach:ignore@1');
      expect(keeping(source, 3), isNull);
    });

    test('keeps a declaration among its doc comment and annotations', () {
      const source = '''
/// Docs.
// ciach:ignore
@deprecated
void kept() {}
''';
      expect(keeping(source, 1, 4), 'ciach:ignore@2');
    });

    test('above the doc comment keeps the declaration', () {
      const source = '''
// ciach:ignore
/// Docs.
void kept() {}
''';
      expect(keeping(source, 2, 3), 'ciach:ignore@1');
    });

    test('keeps nothing across a blank line', () {
      const source = '''
// ciach:ignore

void notKept() {}
''';
      expect(keeping(source, 3), isNull);
    });

    test('after code keeps the declaration named on its line only', () {
      const source = '''
void kept() {} // ciach:ignore
void notKept() {}
''';
      expect(keeping(source, 1), 'ciach:ignore@1');
      expect(keeping(source, 2), isNull);
    });

    test('takes free text after the marker', () {
      const source = '''
// ciach:ignore kept for the widgetbook
void kept() {}
''';
      expect(keeping(source, 2), 'ciach:ignore@1');
    });
  });

  group('// ciach:ignore-start and -end', () {
    test('keep every declaration named between them', () {
      const source = '''
void before() {}
// ciach:ignore-start
void first() {}
class Kept {
  void member() {}
}
// ciach:ignore-end
void after() {}
''';
      expect(keeping(source, 1), isNull);
      expect(keeping(source, 3), 'ciach:ignore-start@2');
      expect(keeping(source, 5), 'ciach:ignore-start@2');
      expect(keeping(source, 8), isNull);
    });

    test('an unclosed range runs to the end of the file, with an issue', () {
      final markers = IgnoreMarkers.parse('''
// ciach:ignore-start
void kept() {}
''');
      expect(markers.keeping(start: 1, nameLine: 1), isNotNull);
      expect(markers.issues, [
        (
          line: 0,
          message:
              '`// ciach:ignore-start` without a `// ciach:ignore-end`; it runs to the end of the file',
        ),
      ]);
    });

    test('a stray end and a nested start are issues', () {
      final markers = IgnoreMarkers.parse('''
// ciach:ignore-end
// ciach:ignore-start
// ciach:ignore-start
// ciach:ignore-end
''');
      expect(markers.issues.map((issue) => issue.line), [0, 2]);
    });
  });

  test('// ciach:ignore-file keeps the file', () {
    const marked = '''
void f() {}
// ciach:ignore-file
''';
    expect(IgnoreMarkers.parse(marked).ignoresFile, isTrue);
    expect(IgnoreMarkers.parse('void f() {}').ignoresFile, isFalse);
  });

  test('an unknown marker is an issue', () {
    final markers = IgnoreMarkers.parse('''
// ciach:ignroe
void f() {}
''');
    expect(markers.isEmpty, isTrue);
    expect(
      markers.issues.single.message,
      startsWith('unknown marker `ciach:ignroe`'),
    );
  });

  test('a marker in a doc comment, a block comment or a string is text', () {
    const source = '''
/// ciach:ignore
void a() {}
/* ciach:ignore */
void b() {}
const text = """
// ciach:ignore-file
""";
void c() {}
''';
    final markers = IgnoreMarkers.parse(source);
    expect(markers.isEmpty, isTrue);
    expect(markers.ignoresFile, isFalse);
    expect(markers.issues, isEmpty);
  });

  test('a marker in commented-out code is text', () {
    const source = '''
/*
// ciach:ignore-file
// ciach:ignore
void old() {}
*/
void f() {}
''';
    final markers = IgnoreMarkers.parse(source);
    expect(markers.ignoresFile, isFalse);
    expect(markers.isEmpty, isTrue);
  });

  test('punctuation may follow a marker', () {
    const source = '''
// ciach:ignore: kept for the widgetbook
void kept() {}
''';
    expect(keeping(source, 2), 'ciach:ignore@1');
  });

  test('a marker after a block comment on the same line counts', () {
    const source = '''
void kept() {} /* legacy */ // ciach:ignore
''';
    expect(keeping(source, 1), 'ciach:ignore@1');
  });

  test('every marker keeping a declaration is among its keepers', () {
    final markers = IgnoreMarkers.parse('''
// ciach:ignore-start
// ciach:ignore
void kept() {}
// ciach:ignore-end
''');
    expect(markers.keepers(start: 2, nameLine: 2), [
      (line: 1, marker: 'ciach:ignore'),
      (line: 0, marker: 'ciach:ignore-start'),
    ]);
  });

  test('a mention of ciach that is no marker is ignored', () {
    final markers = IgnoreMarkers.parse('''
// ciach: the tool
void f() {}
''');
    expect(markers.isEmpty, isTrue);
    expect(markers.issues, isEmpty);
  });
}
