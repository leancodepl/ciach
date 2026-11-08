/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ciach/src/analysis/analyzer_versions.dart';
import 'package:test/test.dart';

/// The members that the supported analyzer versions spell differently. CI
/// runs these tests with each of them.
void main() {
  test(
    '`extensionTypeNamePart` returns the name and type parameters of an extension type',
    () {
      final unit = parseString(
        content: 'extension type Id<T>(T value) {}',
      ).unit;

      final namePart = extensionTypeNamePart(
        unit.declarations.single as ExtensionTypeDeclaration,
      );

      expect(
        (namePart.typeName.lexeme, namePart.typeParameters?.toSource()),
        ('Id', '<T>'),
      );
    },
  );
}
