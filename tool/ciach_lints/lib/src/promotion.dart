/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// Whether `value != null` promotes [value]: a local variable or parameter
/// that only the function that declares it assigns, or a chain of private
/// final fields from `this` or from such a variable, as in `a._b._items`.
///
/// Flow analysis also promotes some variables that fail this test, such as one
/// that only a closure created after the null check assigns, so `false`
/// doesn't mean that the check can't promote [value].
bool isPromotable(Expression value) => switch (value) {
  ThisExpression() => true,
  SimpleIdentifier(
    element: (LocalVariableElement() || FormalParameterElement()) &&
        final Element element,
  ) =>
    _isAssignedOnlyWhereDeclared(element, value),
  SimpleIdentifier(:final element) => _isPromotableField(element),
  PrefixedIdentifier(:final prefix, :final identifier) =>
    _isPromotableField(identifier.element) && isPromotable(prefix),
  PropertyAccess(
    :final target?,
    operator: Token(type: .PERIOD),
    :final propertyName,
  ) =>
    _isPromotableField(propertyName.element) && isPromotable(target),
  _ => false,
};

/// Whether [element] reads a field that a null check can promote: a private
/// final field.
bool _isPromotableField(Element? element) => switch (element) {
  GetterElement(variable: FieldElement(isPromotable: true)) => true,
  _ => false,
};

/// Whether every assignment to [variable], which [reference] reads, is in the
/// function that declares [variable].
bool _isAssignedOnlyWhereDeclared(Element variable, AstNode reference) {
  final writes = _Writes(variable);
  reference.root.accept(writes);
  return writes.functions.every(
    (function) => function == variable.enclosingElement,
  );
}

/// The closure, function, method or constructor that [node] is in, or `null`
/// when [node] is in none, as in a field initializer.
ExecutableElement? _functionOf(AstNode? node) => switch (node) {
  FunctionExpression(:final ExecutableFragment? declaredFragment) ||
  MethodDeclaration(:final ExecutableFragment? declaredFragment) ||
  ConstructorDeclaration(
    :final ExecutableFragment? declaredFragment,
  ) => declaredFragment?.element,
  null => null,
  _ => _functionOf(node.parent),
};

/// Collects the functions that assign a [variable].
class _Writes(final Element variable) extends RecursiveAstVisitor<void> {
  final functions = <ExecutableElement?>{};

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inSetterContext() && node.element == variable) {
      functions.add(_functionOf(node));
    }
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (node.element == variable) {
      functions.add(_functionOf(node));
    }
    super.visitAssignedVariablePattern(node);
  }
}
