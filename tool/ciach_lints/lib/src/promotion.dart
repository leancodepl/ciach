/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

/// Whether `value != null` promotes [value], read at [at]: a local variable
/// or parameter, or a chain of private final fields from `this` or from such
/// a variable, as in `a._b._items`.
///
/// A variable counts only when every assignment to it is in the function
/// that declares it, and when [at] is in that function too or nothing assigns
/// the variable. Flow analysis also promotes some variables that fail this
/// test, such as one that only a closure created after [at] assigns, so
/// `false` doesn't mean that the check can't promote [value].
bool isPromotable(Expression value, AstNode at) => switch (value) {
  ThisExpression() => true,
  SimpleIdentifier(
    element: (LocalVariableElement() || FormalParameterElement()) &&
        final Element variable,
  ) =>
    _isStable(variable, at),
  SimpleIdentifier(:final element) => _isPromotableField(element),
  PrefixedIdentifier(:final prefix, :final identifier) =>
    _isPromotableField(identifier.element) && isPromotable(prefix, at),
  PropertyAccess(
    :final target?,
    operator: Token(type: .PERIOD),
    :final propertyName,
  ) =>
    _isPromotableField(propertyName.element) && isPromotable(target, at),
  _ => false,
};

/// Whether [element] reads a field that a null check can promote: a private
/// final field.
bool _isPromotableField(Element? element) => switch (element) {
  GetterElement(variable: FieldElement(isPromotable: true)) => true,
  _ => false,
};

/// Whether flow analysis keeps a promotion of [variable] at [at]: every
/// assignment to [variable] is in the function that declares it, and [at] is
/// in that function too unless nothing assigns [variable].
bool _isStable(Element variable, AstNode at) {
  final declaration =
      at.thisOrAncestorMatching((node) => node.parent is CompilationUnit) ??
      at.root;
  final writes = _Writes(variable);
  declaration.accept(writes);
  final home = variable.enclosingElement;
  return writes.functions.every((function) => function == home) &&
      (writes.functions.isEmpty || _functionOf(at) == home);
}

/// The closure, function, method or constructor that [node] is in, or `null`
/// when [node] is in none, as in a field initializer.
ExecutableElement? _functionOf(AstNode? node) => switch (node) {
  FunctionExpression(declaredFragment: final ExecutableFragment? fragment) ||
  MethodDeclaration(declaredFragment: final ExecutableFragment? fragment) ||
  ConstructorDeclaration(
    declaredFragment: final ExecutableFragment? fragment,
  ) => fragment?.element,
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
