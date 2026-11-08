/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/source/document_symbol.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:test/test.dart';

void main() {
  /// The range of [line].
  Range lineRange(int line) => .new(
    start: .new(line: line, character: 0),
    end: .new(line: line, character: 1),
  );

  /// An outline node of [kind], named with a name range when [named].
  Outline node(
    OutlineKind kind, {
    bool named = true,
    String? parameters,
    List<Outline> children = const [],
  }) => .new(
    element: .new(
      kind: kind,
      name: kind.name,
      range: named ? lineRange(1) : null,
      parameters: parameters,
    ),
    range: lineRange(0),
    codeRange: lineRange(2),
    children: children,
  );

  test(
    'gives each kind of declaration the symbol kind that the analysis server gives it',
    () {
      expect(
        {
          for (final kind in OutlineKind.values)
            kind: DocumentSymbol.fromOutline(node(kind)).kind,
        },
        {
          OutlineKind.class$: SymbolKind.class$,
          OutlineKind.classTypeAlias: SymbolKind.class$,
          OutlineKind.compilationUnit: SymbolKind.file,
          OutlineKind.constructor: SymbolKind.constructor,
          OutlineKind.enum$: SymbolKind.enum$,
          OutlineKind.enumConstant: SymbolKind.enum$,
          OutlineKind.extension: SymbolKind.namespace,
          OutlineKind.extensionType: SymbolKind.namespace,
          OutlineKind.field: SymbolKind.field,
          OutlineKind.function: SymbolKind.function,
          OutlineKind.functionTypeAlias: SymbolKind.class$,
          OutlineKind.getter: SymbolKind.property,
          OutlineKind.method: SymbolKind.method,
          OutlineKind.mixin: SymbolKind.class$,
          OutlineKind.setter: SymbolKind.property,
          OutlineKind.topLevelVariable: SymbolKind.variable,
          OutlineKind.typeAlias: SymbolKind.object,
          OutlineKind.unitTestGroup: SymbolKind.method,
          OutlineKind.unitTestTest: SymbolKind.method,
        },
      );
    },
  );

  test(
    'takes the code range, the name range as the selection range, the parameters as the detail, and the children',
    () {
      final symbol = DocumentSymbol.fromOutline(
        node(.class$, children: [node(.method, parameters: '(int a)')]),
      );

      expect(
        symbol,
        DocumentSymbol(
          name: r'class$',
          kind: .class$,
          range: lineRange(2),
          selectionRange: lineRange(1),
          children: [
            .new(
              name: 'method',
              kind: .method,
              range: lineRange(2),
              selectionRange: lineRange(1),
              detail: '(int a)',
            ),
          ],
        ),
      );
    },
  );

  test('a declaration without a name range is selected by its code range', () {
    expect(
      DocumentSymbol.fromOutline(node(.function, named: false)).selectionRange,
      lineRange(2),
    );
  });
}
