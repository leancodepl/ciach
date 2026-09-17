import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Position, Range, SelectionRange, SymbolKind;
import 'package:test/test.dart';

/// The structural rules, against node chains shaped like the server's.
void main() {
  late Directory tempDir;
  late String path;
  late SourceIndex sources;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('ciach_syntax_test_');
    path = p.join(tempDir.path, 'a.dart');
    sources = SourceIndex();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  Position at(int line, int character) =>
      Position(line: line, character: character);

  Range range(int l1, int c1, int l2, int c2) =>
      Range(start: at(l1, c1), end: at(l2, c2));

  /// A chain of nodes, innermost first.
  SelectionRange chain(List<Range> ranges) {
    SelectionRange? node;
    for (final r in ranges.reversed) {
      node = SelectionRange(range: r, parent: node);
    }
    return node!;
  }

  SemanticToken token(
    int line,
    int character,
    String text,
    String type, {
    Set<String> modifiers = const {},
  }) => SemanticToken(
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
    sources
      ..cacheLines(path, source.split('\n'))
      ..cacheSemanticTokens(path, tokens);
    for (final MapEntry(key: position, value: node) in nodes.entries) {
      sources.cacheSelectionRange(path, position, node);
    }
  }

  Location ref(int line, int character, int length) => Location(
    uri: File(path).uri.toString(),
    range: Range(start: at(line, character), end: at(line, character + length)),
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

    Candidate enumCandidate() {
      final symbol = DocumentSymbol(
        name: 'Color',
        kind: SymbolKind.enum$,
        range: range(0, 0, 4, 1),
        selectionRange: range(0, 5, 0, 10),
      );
      return Candidate(
        uri: File(path).uri,
        path: path,
        symbol: symbol,
        outline: Outline(
          element: const OutlineElement(kind: .enum$, name: 'Color'),
          range: range(0, 0, 4, 1),
          codeRange: range(0, 0, 4, 1),
          children: const [],
        ),
        container: null,
        isEnumValue: false,
        isPreventInstantiationCtor: false,
      );
    }

    setUp(() => load(source, tokens, nodes));

    test('a reference followed by .values is a values reference', () {
      expect(sources.isDotValuesRef(ref(3, 24, 5)), isTrue);
    });

    test('a bare values in the body counts as own iteration', () {
      expect(sources.enumIteratesOwnValues(enumCandidate()), isTrue);
      expect(sources.valuesTokensIn(enumCandidate()).map((t) => t.line), [
        2,
        3,
      ]);
    });

    test('a values with a receiver is not bare', () {
      // Only the `Color.values` token has nodes: its parent starts at `Color`.
      sources.cacheSemanticTokens(path, [tokens[0], tokens[3]]);
      expect(sources.enumIteratesOwnValues(enumCandidate()), isFalse);
    });
  });

  group('isRedirectingFactory', () {
    // A declaration's node spans its doc comment, as the outline's range does.
    const source = '''
class Foo {
  /// Doc.
  factory Foo.a() = Bar.named;
  factory Foo.b() => Bar();
  Foo.c() : this.a();
}
''';
    final tokens = [
      token(1, 2, '/// Doc.', 'comment', modifiers: {'documentation'}),
      token(2, 2, 'factory', 'keyword'),
      token(2, 10, 'Foo', 'class', modifiers: {'constructor', 'declaration'}),
      token(2, 14, 'a', 'method', modifiers: {'constructor', 'declaration'}),
      token(2, 20, 'Bar', 'class'),
      token(2, 24, 'named', 'method', modifiers: {'constructor'}),
      token(3, 2, 'factory', 'keyword'),
      token(3, 10, 'Foo', 'class', modifiers: {'constructor', 'declaration'}),
      token(3, 14, 'b', 'method', modifiers: {'constructor', 'declaration'}),
      token(3, 21, 'Bar', 'class', modifiers: {'constructor'}),
      token(4, 2, 'Foo', 'class', modifiers: {'constructor', 'declaration'}),
      token(4, 6, 'c', 'method', modifiers: {'constructor', 'declaration'}),
      token(4, 17, 'a', 'method', modifiers: {'constructor'}),
    ];
    final nodes = {
      // named > Bar.named > /// Doc. … = Bar.named; > { … }
      at(2, 24): chain([
        range(2, 24, 2, 29),
        range(2, 20, 2, 29),
        range(1, 2, 2, 30),
        range(0, 10, 5, 1),
      ]),
      // Bar > Bar() > => Bar(); > factory Foo.b() => Bar();
      at(3, 21): chain([
        range(3, 21, 3, 24),
        range(3, 21, 3, 26),
        range(3, 18, 3, 27),
        range(3, 2, 3, 27),
      ]),
    };

    Candidate ctor(
      String name,
      Range codeRange,
      Range nameRange, {
      Range? fullRange,
    }) => Candidate(
      uri: File(path).uri,
      path: path,
      symbol: DocumentSymbol(
        name: name,
        kind: SymbolKind.constructor,
        range: codeRange,
        selectionRange: nameRange,
      ),
      outline: Outline(
        element: OutlineElement(kind: .constructor, name: name),
        range: fullRange ?? codeRange,
        codeRange: codeRange,
        children: const [],
      ),
      container: 'Foo',
      isEnumValue: false,
      isPreventInstantiationCtor: false,
    );

    setUp(() => load(source, tokens, nodes));

    test("a target that is the declaration's own child redirects", () {
      final a = ctor(
        'Foo.a',
        range(2, 2, 2, 30),
        range(2, 14, 2, 15),
        fullRange: range(1, 2, 2, 30),
      );
      expect(sources.redirectProbePosition(a), at(2, 24));
      expect(sources.isRedirectingFactory(a), isTrue);
    });

    test('an expression body does not, nor does a generative constructor', () {
      final b = ctor('Foo.b', range(3, 2, 3, 27), range(3, 14, 3, 15));
      expect(sources.isRedirectingFactory(b), isFalse);
      final c = ctor('Foo.c', range(4, 2, 4, 21), range(4, 6, 4, 7));
      expect(sources.redirectProbePosition(c), isNull);
      expect(sources.isRedirectingFactory(c), isFalse);
    });
  });
}
