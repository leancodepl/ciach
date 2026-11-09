/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:ciach/src/analysis/argument_names.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:test/test.dart';

void main() {
  /// The arguments of the call and the fields of the record in [source].
  List<AstNode> argumentsIn(String source) {
    final initializer =
        (parseString(content: source).unit.declarations.single
                as TopLevelVariableDeclaration)
            .variables
            .variables
            .single
            .initializer;
    return switch (initializer) {
      MethodInvocation(:final argumentList) => argumentList.arguments,
      RecordLiteral(:final fields) => fields,
      _ => throw StateError('$initializer'),
    };
  }

  test(
    'gives the name and the colon of a named argument and a named record field, from analyzer 13.0.0 on, and nothing for a positional one',
    () {
      final arguments = [
        ...argumentsIn('final c = f(x: 1, a ? b : c);'),
        ...argumentsIn('final r = (y: 1, z);'),
      ];
      // Before analyzer 13.0.0, a named argument holds its name in a label.
      final namesAreTokens = arguments.first.childEntities.first is! Label;

      expect(
        [
          for (final argument in arguments)
            argumentNameOf(
              argument,
            )?.let((name) => (name.name.lexeme, name.colon.lexeme)),
        ],
        namesAreTokens
            ? [('x', ':'), null, ('y', ':'), null]
            : [null, null, null, null],
      );
    },
  );
}
