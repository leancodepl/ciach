/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds where the code of a file uses declarations: every name, operator and
/// constructor call that resolves to one.
///
/// It records what the index of `package:analyzer`, which the analysis
/// server searches for references, records against an element, at the same
/// places. It records some uses that this index misses, too: an object
/// called like a function (`obj(1)`) or used where a function is expected
/// uses its `call` method, an operator in a relational pattern (`case < a`)
/// uses that operator, and a primary constructor without `super(…)` calls
/// the super constructor.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/assignments.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// A use of `element` in the text from `offset` to `offset + length`, which is
/// empty for a constructor call that names no constructor (`Foo()`).
typedef ElementUse = ({Element element, int offset, int length});

/// Returns the uses of declarations in [unit]. A use names the declaration,
/// not a member of a generic type with its type arguments applied, and a
/// call of a constructor that a mixin application class forwards uses the
/// constructor that it forwards to.
List<ElementUse> elementUses(CompilationUnit unit) =>
    (_Uses()..visitCompilationUnit(unit)).uses;

final class _Uses extends RecursiveAstVisitor<void> {
  final uses = <ElementUse>[];

  /// Adds a use of [element] from [offset] to [offset] + [length], when ciach
  /// counts its uses.
  void _add(Element? element, int offset, int length) {
    if (element?.baseElement case final declaration?
        when _isCounted(declaration)) {
      uses.add((element: declaration, offset: offset, length: length));
    }
  }

  void _addAt(Element? element, SyntacticEntity at) =>
      _add(element, at.offset, at.length);

  /// Adds a call of [constructor], which [name] names: `.named` from the
  /// period on, or the place right after [type] when it names none, and the
  /// uses of its `this.` parameters that [arguments] passes by name.
  void _addConstructor(
    ConstructorElement? constructor, {
    required SyntacticEntity type,
    Token? period,
    SyntacticEntity? name,
    ArgumentList? arguments,
  }) {
    final declaration = _forwardedTo(constructor);
    if (period != null && name != null) {
      _add(declaration, period.offset, name.end - period.offset);
    } else {
      _add(declaration, type.end, 0);
    }
    _addNamedArguments(declaration, arguments);
  }

  /// Adds the implicit `super()` call that [constructor] makes when its
  /// [initializers] call no super constructor, from [start] to the end of
  /// [end].
  void _addImplicitSuperCall(
    ConstructorElement? constructor,
    Iterable<ConstructorInitializer> initializers,
    SyntacticEntity start,
    SyntacticEntity end,
  ) {
    if (initializers.none(
      (initializer) => initializer is SuperConstructorInvocation,
    )) {
      _add(
        _forwardedTo(constructor?.superConstructor),
        start.offset,
        end.end - start.offset,
      );
    }
  }

  /// Adds the uses of the field formal parameters of [constructor] that
  /// [arguments] passes by name, such as `x` for `this.x` in `Foo(x: 1)`.
  void _addNamedArguments(
    ConstructorElement? constructor,
    ArgumentList? arguments,
  ) {
    if (constructor == null || arguments == null) {
      return;
    }
    final parameters = {
      for (final parameter in constructor.formalParameters)
        if (parameter case FieldFormalParameterElement(
          isNamed: true,
          :final name?,
        ))
          name: parameter,
    };
    // The argument's node type differs between analyzer versions, but each
    // named argument starts with its name and a colon.
    for (final AstNode argument in arguments.arguments) {
      final name = argument.beginToken;
      if (name.next?.type == .COLON) {
        _addAt(parameters[name.lexeme], name);
      }
    }
  }

  @override
  void visitAnnotation(Annotation node) {
    if (node.element case final ConstructorElement constructor) {
      // The name of `@Tag.named()` can be `Tag.named`, whose last identifier
      // then uses the constructor.
      if (node.name.element is ConstructorElement) {
        _addNamedArguments(_forwardedTo(constructor), node.arguments);
      } else {
        _addConstructor(
          constructor,
          type: node.typeArguments ?? node.name,
          period: node.period,
          name: node.constructorName,
          arguments: node.arguments,
        );
      }
    }
    node.name.accept(this);
    node.typeArguments?.accept(this);
    node.arguments?.accept(this);
  }

  @override
  void visitAssignmentExpression(AssignmentExpression node) {
    _addAt(node.element, node.operator);
    super.visitAssignmentExpression(node);
  }

  @override
  void visitBinaryExpression(BinaryExpression node) {
    _addAt(node.element, node.operator);
    super.visitBinaryExpression(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    switch (node) {
      // A class without constructors calls the unnamed super constructor from
      // its name.
      case ClassDeclaration(
        declaredFragment: ClassFragment(
          element: ClassElement(
            constructors: [
              ConstructorElement(
                isOriginImplicitDefault: true,
                :final superConstructor,
              ),
            ],
          ),
        ),
      ):
        _addAt(_forwardedTo(superConstructor), node.namePart.typeName);
      // So does a primary constructor without `super(…)`, from its name.
      case ClassDeclaration(
        namePart: PrimaryConstructorDeclaration(
          :final declaredFragment?,
          :final typeName,
          :final constructorName,
        ),
        :final body,
      ):
        _addImplicitSuperCall(
          declaredFragment.element,
          _initializersOf(body),
          typeName,
          constructorName ?? typeName,
        );
      default:
    }
    super.visitClassDeclaration(node);
  }

  @override
  void visitCommentReference(CommentReference node) {
    switch (node.expression) {
      case PrefixedIdentifier(element: final ConstructorElement constructor) &&
          final name:
        _add(constructor, name.prefix.end, name.end - name.prefix.end);
      case SimpleIdentifier(element: final ConstructorElement constructor) &&
          final name:
        _add(constructor, name.end, 0);
      default:
        super.visitCommentReference(node);
    }
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if (node.typeName ?? node.newKeyword ?? node.factoryKeyword
        case final start?) {
      _addImplicitSuperCall(
        node.declaredFragment?.element,
        node.initializers,
        start,
        node.name ?? start,
      );
    }
    super.visitConstructorDeclaration(node);
  }

  @override
  void visitConstructorFieldInitializer(ConstructorFieldInitializer node) {
    _addAt(node.fieldName.element, node.fieldName);
    node.expression.accept(this);
  }

  @override
  void visitConstructorName(ConstructorName node) {
    _addConstructor(
      node.element,
      type: node.type,
      period: node.period,
      name: node.name,
      arguments: switch (node.parent) {
        InstanceCreationExpression(:final argumentList) => argumentList,
        _ => null,
      },
    );
    node.type.accept(this);
  }

  @override
  void visitDotShorthandConstructorInvocation(
    DotShorthandConstructorInvocation node,
  ) {
    final constructor = _forwardedTo(node.element);
    _addAt(constructor, node.constructorName);
    _addNamedArguments(constructor, node.argumentList);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitDotShorthandInvocation(DotShorthandInvocation node) {
    _addAt(node.memberName.element, node.memberName);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitDotShorthandPropertyAccess(DotShorthandPropertyAccess node) {
    final name = node.propertyName;
    _addAt(switch (name.element) {
      final ConstructorElement constructor => _forwardedTo(constructor),
      final element => element,
    }, name);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    final selector = node.arguments?.constructorSelector;
    _addConstructor(
      node.constructorElement,
      type: node.name,
      period: selector?.period,
      name: selector?.name,
      arguments: node.arguments?.argumentList,
    );
    node.documentationComment?.accept(this);
    node.metadata.accept(this);
    node.arguments?.typeArguments?.accept(this);
    node.arguments?.argumentList.accept(this);
  }

  @override
  void visitExtensionOverride(ExtensionOverride node) {
    _addAt(node.element, node.name);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitFieldFormalParameter(FieldFormalParameter node) {
    if (node.declaredFragment?.element case FieldFormalParameterElement(
      :final field,
    )) {
      _addAt(field, node.name);
    }
    super.visitFieldFormalParameter(node);
  }

  /// Adds the `call` method that `obj(1)` calls.
  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    if (node.element case final MethodElement call) {
      _addAt(call, node.function);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  /// Adds the `call` method of an object used where a function is expected.
  @override
  void visitImplicitCallReference(ImplicitCallReference node) {
    _addAt(node.element, node.expression);
    super.visitImplicitCallReference(node);
  }

  @override
  void visitIndexExpression(IndexExpression node) {
    for (final element in _accessedElements(node, node.element)) {
      _addAt(element, node.leftBracket);
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    _addAt(node.methodName.element, node.methodName);
    node.target?.accept(this);
    node.typeArguments?.accept(this);
    node.argumentList.accept(this);
  }

  @override
  void visitNamedType(NamedType node) {
    _addAt(node.element, node.name);
    node.typeArguments?.accept(this);
  }

  @override
  void visitPatternField(PatternField node) {
    switch (node.name) {
      case PatternFieldName(name: final name?):
        _addAt(node.element, name);
      // A field written `:foo` names its getter with no text, at the colon.
      case final name?:
        _add(node.element, name.offset, 0);
      case null:
    }
    super.visitPatternField(node);
  }

  @override
  void visitPostfixExpression(PostfixExpression node) {
    _addAt(node.element, node.operator);
    super.visitPostfixExpression(node);
  }

  @override
  void visitPrefixExpression(PrefixExpression node) {
    _addAt(node.element, node.operator);
    super.visitPrefixExpression(node);
  }

  @override
  void visitRedirectingConstructorInvocation(
    RedirectingConstructorInvocation node,
  ) {
    _addConstructor(
      node.element,
      type: node.thisKeyword,
      period: node.period,
      name: node.constructorName,
      arguments: node.argumentList,
    );
    node.argumentList.accept(this);
  }

  @override
  void visitRelationalPattern(RelationalPattern node) {
    _addAt(node.element, node.operator);
    super.visitRelationalPattern(node);
  }

  /// Adds the declaration that [node] names, unless [node] declares it or
  /// labels an argument: before analyzer 13.0.0, the name of a named argument
  /// is an identifier, which [_addNamedArguments] has added already.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.inDeclarationContext() || node.parent is Label) {
      return;
    }
    for (final element in _accessedElements(node, node.element)) {
      _addAt(element, node);
    }
  }

  @override
  void visitSuperConstructorInvocation(SuperConstructorInvocation node) {
    _addConstructor(
      node.element,
      type: node.superKeyword,
      period: node.period,
      name: node.constructorName,
      arguments: node.argumentList,
    );
    node.argumentList.accept(this);
  }

  @override
  void visitSuperFormalParameter(SuperFormalParameter node) {
    if (node.declaredFragment?.element case SuperFormalParameterElement(
      :final superConstructorParameter,
    )) {
      _addAt(superConstructorParameter, node.name);
    }
    super.visitSuperFormalParameter(node);
  }

  /// The elements that [node], which names [element], reads and writes: the
  /// setter of an assignment (`x = 1`), the getter and the setter of a
  /// compound assignment (`x += 1`, `x++`), and [element] otherwise.
  static List<Element?> _accessedElements(Expression node, Element? element) =>
      assignmentTo(node)?.let(
        (assignment) => [assignment.readElement, assignment.writeElement],
      ) ??
      [element];

  /// The initializers of the primary constructor in the class [body].
  static Iterable<ConstructorInitializer> _initializersOf(AstNode body) =>
      switch (body) {
        BlockClassBody(:final members) => [
          for (final member in members)
            if (member case PrimaryConstructorBody(:final initializers))
              ...initializers,
        ],
        _ => const [],
      };

  /// The constructor that a call of [constructor] runs: the constructor of
  /// the superclass for one that a mixin application class forwards to it.
  static ConstructorElement? _forwardedTo(ConstructorElement? constructor) {
    var current = constructor?.baseElement;
    while (current != null && _isForwarding(current)) {
      current = current.superConstructor?.baseElement;
    }
    return current;
  }

  static bool _isForwarding(ConstructorElement constructor) =>
      switch (constructor.enclosingElement) {
        ClassElement(isMixinApplication: true) => true,
        _ => false,
      };

  /// Whether ciach counts the uses of [element]: a declaration that an
  /// outline lists, which is no local variable, parameter, type parameter or
  /// import prefix, or a `this.` parameter, whose uses count for its field.
  static bool _isCounted(Element element) => switch (element) {
    InterfaceElement() ||
    ExtensionElement() ||
    TypeAliasElement() ||
    TopLevelFunctionElement() ||
    LocalFunctionElement() ||
    PropertyAccessorElement() ||
    PropertyInducingElement() ||
    MethodElement() ||
    ConstructorElement() ||
    FieldFormalParameterElement() => true,
    _ => false,
  };
}
