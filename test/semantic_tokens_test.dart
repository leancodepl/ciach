import 'dart:io';

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;
import 'package:test/test.dart';

/// The legend the Dart server sends.
const legend = SemanticTokensLegend(
  tokenTypes: [
    'annotation',
    'class',
    'comment',
    'method',
    'variable',
    'parameter',
    'enum',
    'enumMember',
    'type',
    'source',
    'property',
    'keyword',
    'label',
    'namespace',
    'boolean',
    'number',
    'string',
    'function',
    'typeParameter',
  ],
  tokenModifiers: [
    'documentation',
    'constructor',
    'declaration',
    'importPrefix',
    'instance',
    'static',
    'escape',
    'annotation',
    'control',
    'label',
    'interpolation',
    'source',
    'void',
    'wildcard',
  ],
);

int type(String name) => legend.tokenTypes.indexOf(name);
int mods(List<String> names) => names.fold(
  0,
  (bits, name) => bits | (1 << legend.tokenModifiers.indexOf(name)),
);

void main() {
  // The server's tokens for this source, relative-encoded as on the wire.
  const source = '''
/// Doc for [Foo].
@override
void f() {}
''';
  final data = <int>[
    // line 0: `/// Doc for [` — 13 chars, comment/documentation
    0, 0, 13, type('comment'), mods(['documentation']),
    // `Foo`, same line, 13 chars later — class, no modifiers
    0, 13, 3, type('class'), 0,
    // `].`
    0, 3, 2, type('comment'), mods(['documentation']),
    // line 1: `@` then `override` with the annotation modifier
    1, 0, 1, type('annotation'), 0,
    0, 1, 8, type('class'), mods(['annotation']),
    // line 2: `void` keyword, `f` declaration
    1, 0, 4, type('keyword'), mods(['void']),
    0, 5, 1, type('function'), mods(['declaration']),
  ];
  final lines = source.split('\n');

  group('decodeSemanticTokens', () {
    final tokens = decodeSemanticTokens(data, legend, lines);

    test('resolves positions, types, modifiers and text', () {
      expect(tokens.map((t) => t.text).toList(), [
        '/// Doc for [',
        'Foo',
        '].',
        '@',
        'override',
        'void',
        'f',
      ]);
      expect(tokens[1].start, const Position(line: 0, character: 13));
      expect(tokens[1].type, 'class');
      expect(tokens[0].isDocComment, isTrue);
      expect(tokens[2].isDocComment, isTrue);
      expect(tokens[4].isAnnotationNamed('override'), isTrue);
      expect(tokens[4].isAnnotationNamed('Override'), isFalse);
      expect(tokens[5].isKeyword, isTrue);
      expect(tokens[5].modifiers, {'void'});
      expect(tokens[6].modifiers, {'declaration'});
    });

    test('drops a token outside the legend or the file', () {
      final decoded = decodeSemanticTokens(
        [
          0, 0, 4, 99, 0, // unknown type; the cursor still advances past it
          ...data.take(5),
          5, 0, 1, type('keyword'), 0, // line 5 does not exist
        ],
        legend,
        lines,
      );
      expect(decoded.map((t) => t.text), ['/// Doc for [']);
    });

    test("lookups find a line's first token and a token by start", () {
      expect(tokens.firstOnLine(0)?.text, '/// Doc for [');
      expect(tokens.firstOnLine(1)?.text, '@');
      expect(tokens.firstOnLine(7), isNull);
      expect(
        tokens.startingAt(const Position(line: 0, character: 13))?.text,
        'Foo',
      );
      expect(tokens.startingAt(const Position(line: 0, character: 14)), isNull);
      expect(
        tokens
            .between(
              const Position(line: 0, character: 0),
              const Position(line: 2, character: 0),
            )
            .map((t) => t.text),
        ['/// Doc for [', 'Foo', '].', '@', 'override'],
      );
    });
  });

  group('SourceIndex with cached tokens', () {
    late Directory tempDir;
    late String path;
    late SourceIndex sources;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ciach_tokens_test_');
      path = p.join(tempDir.path, 'a.dart');
      File(path).writeAsStringSync(source);
      sources = SourceIndex()
        ..cacheLines(path, lines)
        ..cacheSemanticTokens(path, decodeSemanticTokens(data, legend, lines));
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    Location at(int line, int character) => Location(
      uri: File(path).uri.toString(),
      range: Range(
        start: Position(line: line, character: character),
        end: Position(line: line, character: character + 1),
      ),
    );

    test('a reference on a doc-comment line is a doc reference', () {
      expect(sources.isDocReference(at(0, 13)), isTrue);
      expect(sources.isDocReference(at(2, 5)), isFalse);
    });

    test('a file without tokens yields no doc references', () {
      final other = p.join(tempDir.path, 'b.dart');
      File(other).writeAsStringSync('/// [Foo]\n');
      expect(
        sources.isDocReference(
          Location(
            uri: File(other).uri.toString(),
            range: const Range(
              start: Position(line: 0, character: 5),
              end: Position(line: 0, character: 8),
            ),
          ),
        ),
        isFalse,
      );
    });

    test('leading metadata is the tokens before the code', () {
      final outline = Outline.fromJson({
        'element': {'kind': 'FUNCTION', 'name': 'f'},
        'range': {
          'start': {'line': 0, 'character': 0},
          'end': {'line': 2, 'character': 11},
        },
        'codeRange': {
          'start': {'line': 2, 'character': 0},
          'end': {'line': 2, 'character': 11},
        },
      });
      expect(sources.leadingMetadata(path, outline).map((t) => t.text), [
        '/// Doc for [',
        'Foo',
        '].',
        '@',
        'override',
      ]);
    });
  });
}
