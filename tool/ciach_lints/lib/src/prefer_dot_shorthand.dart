import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a static member, enum value or constructor spelled with its type
/// name where the context type already names that type, so a dot shorthand
/// (`.plain`, `.new(path, c)`) would do.
class PreferDotShorthand() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_dot_shorthand',
    "The context type is already '{0}'; a dot shorthand can leave it out.",
    correctionMessage: "Try replacing '{0}.{1}' with '.{1}'.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context.typeSystem);
    registry
      ..addPrefixedIdentifier(this, visitor)
      ..addPropertyAccess(this, visitor)
      ..addMethodInvocation(this, visitor)
      ..addInstanceCreationExpression(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule, final TypeSystem typeSystem)
    extends SimpleAstVisitor<void> {
  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) => _check(node);

  @override
  void visitPropertyAccess(PropertyAccess node) => _check(node);

  @override
  void visitMethodInvocation(MethodInvocation node) => _check(node);

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) =>
      _check(node);

  void _check(Expression node) {
    final spelling = spellingOf(node);
    if (spelling == null) {
      return;
    }
    final context = contextTypeOf(node);
    if (context == null || namespaceOf(context, typeSystem) != spelling.type) {
      return;
    }
    rule.reportAtNode(node, arguments: [spelling.typeName, spelling.member]);
  }
}

/// A type name spelled out before a member, and what to do with it: the
/// `typeRange` replaced by the `replacement` turns the expression into a dot
/// shorthand.
typedef Spelling = ({
  InterfaceElement type,
  String typeName,
  String member,
  SourceRange typeRange,
  String replacement,
});

/// [node]'s [Spelling], or `null` when it is not a static member access, an
/// enum value, a static method call or a constructor call spelled with its
/// type name. Explicit type arguments stay out: a shorthand has nowhere to put
/// them.
Spelling? spellingOf(Expression node) => switch (node) {
  PrefixedIdentifier(
    prefix: Identifier(element: final InterfaceElement type) && final prefix,
    :final identifier,
  ) =>
    _deleting(type, prefix, identifier.name),
  PropertyAccess(
    target: Identifier(element: final InterfaceElement type) && final target,
    :final propertyName,
  ) =>
    _deleting(type, target, propertyName.name),
  MethodInvocation(
    target: Identifier(element: final InterfaceElement type) && final target,
    typeArguments: null,
    :final methodName,
  ) =>
    _deleting(type, target, methodName.name),
  InstanceCreationExpression(
    constructorName: ConstructorName(
      type: NamedType(
            element: final InterfaceElement type,
            typeArguments: null,
          ) &&
          final namedType,
      :final name,
    ),
  ) =>
    (
      type: type,
      typeName: namedType.toSource(),
      member: name?.name ?? 'new',
      typeRange: range.node(namedType),
      replacement: name == null ? '.new' : '',
    ),
  _ => null,
};

Spelling _deleting(InterfaceElement type, Expression typeNode, String member) =>
    (
      type: type,
      typeName: typeNode.toSource(),
      member: member,
      typeRange: range.node(typeNode),
      replacement: '',
    );

/// The declaration a dot shorthand in a context of type [type] resolves
/// against: the type itself, its non-nullable form, or what its `FutureOr`
/// wraps.
InterfaceElement? namespaceOf(DartType type, TypeSystem typeSystem) {
  var namespace = typeSystem.promoteToNonNull(type);
  while (namespace.isDartAsyncFutureOr) {
    namespace = typeSystem.promoteToNonNull(
      (namespace as InterfaceType).typeArguments.single,
    );
  }
  return switch (namespace) {
    InterfaceType(:final element) => element,
    _ => null,
  };
}

/// The type the context imposes on [node], as far as a dot shorthand needs
/// it: `null` when nothing does, or when a type parameter of the invoked
/// function would have to be inferred from [node] itself. An annotation's
/// arguments get `null` too: tools read annotations with parsers of their
/// own (`package:test` evaluates `@Timeout` itself), and those may not know
/// the shorthand.
DartType? contextTypeOf(Expression node) {
  final parent = node.parent;
  return switch (parent) {
    ArgumentList(parent: Annotation()) => null,
    ArgumentList() => _parameterType(node.correspondingParameter),
    NamedArgument(argumentExpression: final e) when e == node => _parameterType(
      parent.correspondingParameter,
    ),
    VariableDeclaration(initializer: final e, parent: final list)
        when e == node && list is VariableDeclarationList =>
      list.type?.type,
    ReturnStatement(expression: final e) when e == node => _returnedTypeOf(
      parent.thisOrAncestorOfType<FunctionBody>(),
    ),
    ExpressionFunctionBody(expression: final e) when e == node =>
      _returnedTypeOf(parent),
    AssignmentExpression(rightHandSide: final e, :final operator)
        when e == node &&
            (operator.type == TokenType.EQ ||
                operator.type == TokenType.QUESTION_QUESTION_EQ) =>
      parent.writeType,
    BinaryExpression(rightOperand: final e, :final operator)
        when e == node &&
            (operator.type == TokenType.EQ_EQ ||
                operator.type == TokenType.BANG_EQ) =>
      parent.leftOperand.staticType,
    BinaryExpression(rightOperand: final e, :final operator)
        when e == node && operator.type == TokenType.QUESTION_QUESTION =>
      contextTypeOf(parent),
    ParenthesizedExpression() => contextTypeOf(parent),
    ConditionalExpression(thenExpression: final t, elseExpression: final e)
        when t == node || e == node =>
      contextTypeOf(parent),
    SwitchExpressionCase(expression: final e, parent: final switch_)
        when e == node && switch_ is SwitchExpression =>
      contextTypeOf(switch_),
    FormalParameterDefaultClause(value: final e, parent: final parameter)
        when e == node && parameter is FormalParameter =>
      parameter.declaredFragment?.element.type,
    ConstantPattern(expression: final e) when e == node =>
      parent.matchedValueType,
    ListLiteral() => _elementTypeOf(parent, 0),
    SetOrMapLiteral(isSet: true) => _elementTypeOf(parent, 0),
    MapLiteralEntry(key: final k, value: final v, parent: final map)
        when map is SetOrMapLiteral =>
      _elementTypeOf(map, k == node ? 0 : 1).takeIf(k == node || v == node),
    IfElement(thenElement: final t, elseElement: final e)
        when t == node || e == node =>
      _collectionContextOf(parent),
    ForElement(body: final b) when b == node => _collectionContextOf(parent),
    _ => null,
  };
}

/// What [parameter]'s declaration says once substituted, unless the
/// declaration mentions a type parameter of the function itself: that one is
/// inferred from the argument, so the argument has no context to lean on.
DartType? _parameterType(FormalParameterElement? parameter) {
  if (parameter == null) {
    return null;
  }
  if (parameter.enclosingElement case final ExecutableElement function
      when _mentionsAny(
        parameter.baseElement.type,
        function.baseElement.typeParameters.toSet(),
      )) {
    return null;
  }
  return parameter.type;
}

bool _mentionsAny(DartType type, Set<TypeParameterElement> parameters) =>
    switch (type) {
      TypeParameterType(:final element) => parameters.contains(element),
      InterfaceType(:final typeArguments) => typeArguments.any(
        (t) => _mentionsAny(t, parameters),
      ),
      FunctionType(:final returnType, :final formalParameters) =>
        _mentionsAny(returnType, parameters) ||
            formalParameters.any((p) => _mentionsAny(p.type, parameters)),
      RecordType(:final positionalFields, :final namedFields) =>
        positionalFields.any((f) => _mentionsAny(f.type, parameters)) ||
            namedFields.any((f) => _mentionsAny(f.type, parameters)),
      _ => false,
    };

/// The type a `return` in [body] has to produce, from the declared return
/// type of the function the body belongs to; `null` for a lambda, whose
/// return type is only inferred, and for a generator.
DartType? _returnedTypeOf(FunctionBody? body) {
  if (body == null || body.isGenerator) {
    return null;
  }
  final declared = switch (body.parent) {
    MethodDeclaration(:final returnType) => returnType?.type,
    FunctionExpression(parent: FunctionDeclaration(:final returnType)) =>
      returnType?.type,
    _ => null,
  };
  if (declared == null) {
    return null;
  }
  return body.isAsynchronous ? _futureArgument(declared) : declared;
}

/// `T` for a `Future<T>` or `FutureOr<T>` [type], which an `async` body
/// returns a `T` into; `null` otherwise.
DartType? _futureArgument(DartType type) => switch (type) {
  InterfaceType(:final typeArguments)
      when type.isDartAsyncFuture || type.isDartAsyncFutureOr =>
    typeArguments.single,
  _ => null,
};

/// The context type of the elements of [element], a collection element
/// standing in for its parent literal's elements.
DartType? _collectionContextOf(CollectionElement element) =>
    switch (element.parent) {
      final ListLiteral list => _elementTypeOf(list, 0),
      final SetOrMapLiteral set when set.isSet => _elementTypeOf(set, 0),
      final IfElement outer => _collectionContextOf(outer),
      final ForElement outer => _collectionContextOf(outer),
      _ => null,
    };

/// Type argument [index] of [literal]'s type, when its own type arguments or
/// its context fix it rather than its elements: `[Style.plain]` alone infers
/// `List<Style>` from the element, which a shorthand could no longer do.
DartType? _elementTypeOf(TypedLiteral literal, int index) {
  if (literal.typeArguments case final arguments?) {
    return arguments.arguments.elementAtOrNull(index)?.type;
  }
  final context = contextTypeOf(literal);
  if (context == null) {
    return null;
  }
  final literalType = literal.staticType;
  final contextType = _nonNull(context);
  if (literalType is InterfaceType &&
      contextType is InterfaceType &&
      contextType.element == literalType.element) {
    return contextType.typeArguments.elementAtOrNull(index);
  }
  return null;
}

DartType _nonNull(DartType type) => switch (type) {
  InterfaceType(nullabilitySuffix: NullabilitySuffix.question) =>
    type.element.instantiate(
      typeArguments: type.typeArguments,
      nullabilitySuffix: NullabilitySuffix.none,
    ),
  _ => type,
};

extension<T extends Object> on T? {
  T? takeIf(bool condition) => condition ? this : null;
}

/// Rewrites the flagged expression into its dot shorthand.
class ReplaceWithDotShorthand({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.replaceWithDotShorthand',
    DartFixKindPriority.standard,
    'Replace with a dot shorthand',
  );

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final expression = node;
    if (expression is! Expression) {
      return;
    }
    final spelling = spellingOf(expression);
    if (spelling == null) {
      return;
    }
    await builder.addDartFileEdit(
      file,
      (builder) => builder.addSimpleReplacement(
        spelling.typeRange,
        spelling.replacement,
      ),
    );
  }
}
