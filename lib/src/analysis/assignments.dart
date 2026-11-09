/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';

/// Returns the assignment, or the `++` or `--` expression, that writes
/// [node], alone or as the name after a `.`: `x` in `x = 1`, `a.x += 1` and
/// `x++`. Returns `null` when nothing writes [node].
CompoundAssignmentExpression? assignmentTo(Expression node) {
  final target = switch (node.parent) {
    PrefixedIdentifier(:final identifier) && final parent
        when identifier == node =>
      parent,
    PropertyAccess(:final propertyName) && final parent
        when propertyName == node =>
      parent,
    _ => node,
  };
  return switch (target.parent) {
    AssignmentExpression(:final leftHandSide, writeElement: _?) &&
        final CompoundAssignmentExpression assignment ||
    PrefixExpression(operand: final leftHandSide, writeElement: _?) &&
        final CompoundAssignmentExpression assignment ||
    PostfixExpression(operand: final leftHandSide, writeElement: _?) &&
        final CompoundAssignmentExpression assignment
        when leftHandSide == target =>
      assignment,
    _ => null,
  };
}
