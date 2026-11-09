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
    'reports each kind of declaration with the kind that `--kinds` selects',
    () {
      expect(
        {
          for (final kind in OutlineKind.values)
            kind: OutlineElement(kind: kind, name: kind.name).reportedKind,
        },
        {
          OutlineKind.class$: SymbolKind.class$,
          OutlineKind.classTypeAlias: SymbolKind.class$,
          OutlineKind.compilationUnit: SymbolKind.file,
          OutlineKind.constructor: SymbolKind.constructor,
          OutlineKind.enum$: SymbolKind.enum$,
          OutlineKind.enumConstant: SymbolKind.enumMember,
          OutlineKind.extension: SymbolKind.namespace,
          OutlineKind.extensionType: SymbolKind.struct,
          OutlineKind.field: SymbolKind.field,
          OutlineKind.function: SymbolKind.function,
          OutlineKind.functionTypeAlias: SymbolKind.object,
          OutlineKind.getter: SymbolKind.property,
          OutlineKind.method: SymbolKind.method,
          OutlineKind.mixin: SymbolKind.interface$,
          OutlineKind.setter: SymbolKind.property,
          OutlineKind.topLevelVariable: SymbolKind.variable,
          OutlineKind.typeAlias: SymbolKind.object,
          OutlineKind.unitTestGroup: SymbolKind.method,
          OutlineKind.unitTestTest: SymbolKind.method,
        },
      );
    },
  );
}
