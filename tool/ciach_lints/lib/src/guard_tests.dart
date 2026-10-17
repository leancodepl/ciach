/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';

/// The test that an [operand] of a `when` clause makes on a [variable].
sealed class GuardTest(
  final Expression operand,
  final SimpleIdentifier variable,
);

/// `variable is type`.
final class TypeTest(super.operand, super.variable, final TypeAnnotation type)
    extends GuardTest;

/// `variable != null`.
final class NullTest(super.operand, super.variable) extends GuardTest;

/// A test that the [pattern] makes, such as `> 0` or `true`. When the
/// pattern matches one value only, so that the variable is redundant,
/// [pinnedType] is the type of that value.
final class ValueTest(
  super.operand,
  super.variable,
  final String pattern, {
  final DartType? pinnedType,
}) extends GuardTest {
  bool get pinsValue => pinnedType != null;
}

/// Relational operators and the operators they become when their operands
/// swap places: `0 < v` is `v > 0`.
const _swapped = {
  '==': '==',
  '!=': '!=',
  '<': '>',
  '<=': '>=',
  '>': '<',
  '>=': '<=',
};

/// The test that [operand] makes on one variable, or `null` when it makes
/// none that a pattern can make.
GuardTest? guardTestOf(Expression operand) => switch (operand) {
  IsExpression(
    expression: final SimpleIdentifier variable,
    notOperator: null,
    :final type,
  ) =>
    TypeTest(operand, variable, type),
  BinaryExpression(
    operator: Token(type: .BANG_EQ),
    leftOperand: final SimpleIdentifier variable,
    rightOperand: NullLiteral(),
  ) ||
  BinaryExpression(
    operator: Token(type: .BANG_EQ),
    leftOperand: NullLiteral(),
    rightOperand: final SimpleIdentifier variable,
  ) => NullTest(operand, variable),
  BinaryExpression(
    :final operator,
    leftOperand: final SimpleIdentifier variable,
    :final rightOperand,
  )
      when _swapped.containsKey(operator.lexeme) && _isConstant(rightOperand) =>
    _comparison(operand, variable, operator.lexeme, rightOperand),
  BinaryExpression(
    :final operator,
    :final leftOperand,
    rightOperand: final SimpleIdentifier variable,
  )
      when _swapped.containsKey(operator.lexeme) && _isConstant(leftOperand) =>
    _comparison(operand, variable, _swapped[operator.lexeme]!, leftOperand),
  SimpleIdentifier(:final staticType) when _isBool(staticType) => ValueTest(
    operand,
    operand,
    'true',
    pinnedType: staticType,
  ),
  PrefixExpression(
    operator: Token(type: .BANG),
    operand: final SimpleIdentifier variable,
  )
      when _isBool(variable.staticType) =>
    ValueTest(operand, variable, 'false', pinnedType: variable.staticType),
  _ => null,
};

/// The test `variable <operator> constant` that [operand] makes.
ValueTest _comparison(
  Expression operand,
  SimpleIdentifier variable,
  String operator,
  Expression constant,
) => switch (operator) {
  '==' => ValueTest(
    operand,
    variable,
    constant.toSource(),
    pinnedType: constant.staticType,
  ),
  _ => ValueTest(operand, variable, '$operator ${constant.toSource()}'),
};

/// Whether [type] is `bool`, not `bool?`.
bool _isBool(DartType? type) =>
    type != null &&
    type.isDartCoreBool &&
    type.nullabilitySuffix == NullabilitySuffix.none;

/// Whether [expression] can be a constant pattern: a literal, a negated
/// number, or the name of a constant.
bool _isConstant(Expression expression) => switch (expression) {
  BooleanLiteral() ||
  IntegerLiteral() ||
  DoubleLiteral() ||
  NullLiteral() ||
  SimpleStringLiteral() ||
  PrefixExpression(
    operator: Token(type: .MINUS),
    operand: IntegerLiteral() || DoubleLiteral(),
  ) => true,
  SimpleIdentifier(:final element) ||
  PrefixedIdentifier(:final element) ||
  PropertyAccess(
    target: Identifier(),
    propertyName: SimpleIdentifier(:final element),
  ) ||
  DotShorthandPropertyAccess(
    propertyName: SimpleIdentifier(:final element),
  ) => switch (element) {
    PropertyAccessorElement(:final variable) => variable.isConst,
    VariableElement(:final isConst) => isConst,
    _ => false,
  },
  _ => false,
};
