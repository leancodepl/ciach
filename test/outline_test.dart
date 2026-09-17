import 'package:ciach/src/conventions/serialization.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;
import 'package:test/test.dart';

Map<String, Object?> range(int l1, int c1, int l2, int c2) => {
  'start': {'line': l1, 'character': c1},
  'end': {'line': l2, 'character': c2},
};

void main() {
  group('Outline.fromJson', () {
    // As the server publishes it for:
    //
    //   /// Doc.
    //   @Deprecated('x')
    //   class Foo {
    //     /// Field doc.
    //     final int a;
    //   }
    final json = <String, Object?>{
      'element': {'kind': 'CLASS', 'name': 'Foo', 'range': range(2, 6, 2, 9)},
      'range': range(0, 0, 5, 1),
      'codeRange': range(2, 0, 5, 1),
      'children': [
        {
          'element': {
            'kind': 'FIELD',
            'name': 'a',
            'range': range(4, 12, 4, 13),
            'returnType': 'int',
          },
          'range': range(3, 2, 4, 14),
          'codeRange': range(4, 12, 4, 13),
        },
      ],
    };

    test('reads kinds, names, ranges and children', () {
      final outline = Outline.fromJson(json);
      expect(outline.element.kind, OutlineKind.class$);
      expect(outline.element.name, 'Foo');
      expect(
        outline.element.range?.start,
        const Position(line: 2, character: 6),
      );
      expect(outline.range.start, const Position(line: 0, character: 0));
      expect(outline.codeRange.start, const Position(line: 2, character: 0));
      expect(outline.hasLeadingMetadata, isTrue);

      final field = outline.children.single;
      expect(field.element.kind, OutlineKind.field);
      expect(field.element.returnType, 'int');
      expect(field.range.start, const Position(line: 3, character: 2));
      expect(field.codeRange.end, const Position(line: 4, character: 13));
      expect(field.children, isEmpty);
    });

    test('lists every node depth-first, the root first', () {
      expect(
        Outline.fromJson(json).descendants.map((n) => n.element.name).toList(),
        ['Foo', 'a'],
      );
    });

    test('falls back to the range when codeRange is absent', () {
      final outline = Outline.fromJson({
        'element': {'kind': 'FUNCTION', 'name': 'f'},
        'range': range(1, 0, 1, 10),
      });
      expect(outline.codeRange, outline.range);
      expect(outline.hasLeadingMetadata, isFalse);
      expect(outline.element.range, isNull);
    });

    test('keeps an unknown kind rather than failing', () {
      expect(OutlineKind.fromWire('LIBRARY'), OutlineKind.other);
      expect(OutlineKind.fromWire('EXTENSION_TYPE'), OutlineKind.extensionType);
    });
  });

  group('OutlineElement.isUnnamedExtension', () {
    OutlineElement element(String kind, String name) =>
        OutlineElement(kind: OutlineKind.fromWire(kind), name: name);

    test('recognizes the name the server synthesizes', () {
      expect(
        element('EXTENSION', 'extension on String').isUnnamedExtension,
        isTrue,
      );
      expect(
        element('EXTENSION', 'extension on List<T>').isUnnamedExtension,
        isTrue,
      );
    });

    test('a named extension, or another kind, is not one', () {
      expect(element('EXTENSION', 'IntX').isUnnamedExtension, isFalse);
      expect(
        element('CLASS', 'extension on String').isUnnamedExtension,
        isFalse,
      );
    });
  });

  group('isJsonValueType', () {
    test('accepts JSON value types, nullable or parameterized', () {
      for (final type in [
        'Map<String, dynamic>',
        'List<int>?',
        'String',
        'num',
        'Object?',
        'dynamic',
        'Map<String, Object?> ',
      ]) {
        expect(isJsonValueType(type), isTrue, reason: type);
      }
    });

    test('rejects other types and an omitted one', () {
      for (final type in [
        'Widget',
        'MapEntry<int, int>',
        'Strings',
        '',
        null,
      ]) {
        expect(isJsonValueType(type), isFalse, reason: '$type');
      }
    });
  });
}
