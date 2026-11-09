import 'dart:io';

import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/selection_range.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fake_syntax.dart';

/// The structural rules, against node chains shaped like the server's.
void main() {
  late Directory tempDir;
  late String path;
  late FakeSyntax syntax;
  late SourceIndex sources;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_syntax_test_');
    path = p.join(tempDir.path, 'a.dart');
    syntax = .new();
    sources = .new(syntax);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Position at(int line, int character) =>
      .new(line: line, character: character);

  Range range(int l1, int c1, int l2, int c2) =>
      .new(start: at(l1, c1), end: at(l2, c2));

  /// A chain of nodes, innermost first.
  SelectionRange chain(List<Range> ranges) {
    SelectionRange? node;
    for (final r in ranges.reversed) {
      node = .new(range: r, parent: node);
    }
    return node!;
  }

  SemanticToken token(
    int line,
    int character,
    String text,
    String type, {
    Set<String> modifiers = const {},
  }) => .new(
    line: line,
    character: character,
    length: text.length,
    type: type,
    modifiers: modifiers,
    text: text,
  );

  /// Loads [source] into [sources] with the given tokens and node chains.
  void load(
    String source,
    List<SemanticToken> tokens,
    Map<Position, SelectionRange> nodes,
  ) {
    File(path).writeAsStringSync(source);
    sources.cacheLines(path, source.split('\n'));
    syntax.tokens[path] = tokens;
    syntax.nodes[path] = nodes;
  }

  Location ref(int line, int character, int length) => .new(
    path: path,
    range: .new(start: at(line, character), end: at(line, character + length)),
  );

  group('isPatternRef', () {
    const source = '''
String describe(Shape s) => switch (s) {
  Circle() => 'circle',
};
void f(Shape s) {
  if (s case Circle()) {}
  final c = Circle();
}
''';
    final tokens = [
      token(0, 28, 'switch', 'keyword', modifiers: {'control'}),
      token(1, 2, 'Circle', 'class'),
      token(4, 2, 'if', 'keyword', modifiers: {'control'}),
      token(4, 8, 'case', 'keyword', modifiers: {'control'}),
      token(4, 13, 'Circle', 'class'),
      token(5, 2, 'final', 'keyword'),
      token(5, 12, 'Circle', 'class', modifiers: {'constructor'}),
    ];
    final nodes = {
      // Circle > Circle() > Circle() => 'circle' > switch (s) {…}
      at(1, 2): chain([
        range(1, 2, 1, 8),
        range(1, 2, 1, 10),
        range(1, 2, 1, 22),
        range(0, 28, 2, 1),
      ]),
      // Circle > Circle() > case Circle() > if (…) {}
      at(4, 13): chain([
        range(4, 13, 4, 19),
        range(4, 13, 4, 21),
        range(4, 8, 4, 21),
        range(4, 2, 4, 25),
      ]),
      // Circle > Circle() > final c = Circle() > { … }
      at(5, 12): chain([
        range(5, 12, 5, 18),
        range(5, 12, 5, 20),
        range(5, 2, 5, 20),
        range(3, 16, 6, 1),
      ]),
    };

    setUp(() => load(source, tokens, nodes));

    test('a switch-expression arm and an if-case are patterns', () {
      expect(sources.isPatternRef(ref(1, 2, 6)), isTrue);
      expect(sources.isPatternRef(ref(4, 13, 6)), isTrue);
    });

    test('a construction is not, nor is a position without nodes', () {
      expect(sources.isPatternRef(ref(5, 12, 6)), isFalse);
      expect(sources.isPatternRef(ref(0, 16, 5)), isFalse);
    });
  });

  group('.values', () {
    const source = '''
enum Color {
  red;
  static bool any2(bool Function(Color) f) => values.any(f);
  bool has(Object x) => Color.values.contains(x) || x.values;
}
''';
    final tokens = [
      token(0, 5, 'Color', 'enum', modifiers: {'declaration'}),
      token(2, 46, 'values', 'property', modifiers: {'static'}),
      token(3, 24, 'Color', 'enum'),
      token(3, 30, 'values', 'property', modifiers: {'static'}),
      token(3, 54, 'values', 'source'),
    ];
    final nodes = {
      // bare: values > values.any(f)
      at(2, 46): chain([range(2, 46, 2, 52), range(2, 46, 2, 59)]),
      // qualified, at the enum name: Color > Color.values > Color.values.contains(x)
      at(3, 24): chain([
        range(3, 24, 3, 29),
        range(3, 24, 3, 36),
        range(3, 24, 3, 48),
      ]),
      // qualified, at `values`: values > Color.values
      at(3, 30): chain([range(3, 30, 3, 36), range(3, 24, 3, 36)]),
    };

    setUp(() => load(source, tokens, nodes));

    test('a reference followed by .values is a values reference', () {
      expect(sources.isDotValuesRef(ref(3, 24, 5)), isTrue);
    });
  });

  group('isStatePairingReference', () {
    const source = '''
class _S extends State<Foo> {
  State<Foo> s = State<Foo>();
}
''';
    final tokens = [
      token(0, 0, 'class', 'keyword'),
      token(0, 6, '_S', 'class', modifiers: {'declaration'}),
      token(0, 9, 'extends', 'keyword'),
      token(0, 17, 'State', 'class'),
      token(0, 23, 'Foo', 'class'),
      token(1, 2, 'State', 'class'),
      token(1, 8, 'Foo', 'class'),
      token(1, 13, 's', 'variable', modifiers: {'declaration', 'instance'}),
      token(1, 17, 'State', 'class', modifiers: {'constructor'}),
      token(1, 23, 'Foo', 'class'),
    ];
    final nodes = {
      // Foo > <Foo> > State<Foo> > extends State<Foo> > class …
      at(0, 23): chain([
        range(0, 23, 0, 26),
        range(0, 22, 0, 27),
        range(0, 17, 0, 27),
        range(0, 9, 0, 27),
        range(0, 0, 2, 1),
      ]),
      // Foo > <Foo> > State<Foo> > State<Foo> s = State<Foo>(); > { … }
      at(1, 8): chain([
        range(1, 8, 1, 11),
        range(1, 7, 1, 12),
        range(1, 2, 1, 12),
        range(1, 2, 1, 30),
        range(0, 28, 2, 1),
      ]),
    };

    setUp(() => load(source, tokens, nodes));

    test('the type argument of State in an extends clause pairs', () {
      expect(sources.isStatePairingReference('Foo', ref(0, 23, 3)), isTrue);
      expect(sources.isStatePairingReference('Bar', ref(0, 23, 3)), isFalse);
    });

    test('a State<Foo> type annotation elsewhere is a real use', () {
      expect(sources.isStatePairingReference('Foo', ref(1, 8, 3)), isFalse);
    });
  });
}
