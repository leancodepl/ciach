/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:test/test.dart';

void main() {
  test(
    'reports each kind of declaration with the kind that `--kinds` selects, and a file or a test with none',
    () {
      expect(
        {
          for (final kind in OutlineKind.values)
            kind: OutlineElement(kind: kind, name: kind.name).reportedKind,
        },
        {
          OutlineKind.class$: SymbolKind.class$,
          OutlineKind.classTypeAlias: SymbolKind.class$,
          OutlineKind.compilationUnit: null,
          OutlineKind.constructor: SymbolKind.constructor,
          OutlineKind.enum$: SymbolKind.enum$,
          OutlineKind.enumConstant: SymbolKind.enumValue,
          OutlineKind.extension: SymbolKind.extension,
          OutlineKind.extensionType: SymbolKind.extensionType,
          OutlineKind.field: SymbolKind.field,
          OutlineKind.function: SymbolKind.function,
          OutlineKind.functionTypeAlias: SymbolKind.typedef,
          OutlineKind.getter: SymbolKind.property,
          OutlineKind.method: SymbolKind.method,
          OutlineKind.mixin: SymbolKind.mixin,
          OutlineKind.setter: SymbolKind.property,
          OutlineKind.topLevelVariable: SymbolKind.variable,
          OutlineKind.typeAlias: SymbolKind.typedef,
          OutlineKind.unitTestGroup: null,
          OutlineKind.unitTestTest: null,
        },
      );
    },
  );
}
