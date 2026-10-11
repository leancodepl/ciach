import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/precedence.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags an expression that only checks a value for null before using it:
/// `switch (x) { final v? => f(v), null => d }`, `x == null ? null : f(x)`
/// and `x == null ? d : f(x)`. A null-aware chain (`x?.length`) or `x?.let(f)`
/// from `lib/src/extensions.dart`, with `?? d` for a fallback other than
/// `null`, says the same in one expression.
class PreferLet() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_let',
    "This {0} only checks for null; a null-aware chain or '?.let' says the same in one expression.",
    correctionMessage: "Try replacing the {0} with '{1}'.",
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
      ..addSwitchExpression(this, visitor)
      ..addConditionalExpression(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule, final TypeSystem typeSystem)
    extends SimpleAstVisitor<void> {
  @override
  void visitSwitchExpression(SwitchExpression node) => _check(node, 'switch');

  @override
  void visitConditionalExpression(ConditionalExpression node) =>
      _check(node, 'conditional');

  void _check(Expression node, String kind) {
    final shape = letShapeOf(node, typeSystem);
    if (shape == null) {
      return;
    }
    final rewrite = rewriteOf(shape, (node) => node.toSource());
    rule.reportAtNode(node, arguments: [kind, rewrite.sketch]);
  }
}

/// What a null-aware chain or `x?.let(f)` can replace: the `target` checked
/// against null, the name and, when spelled, the type of the `variable` bound
/// to its non-null value, the `body` computed from that, and the `fallback`
/// produced for null when it is not `null` itself.
typedef LetShape = ({
  Expression target,
  String variable,
  TypeAnnotation? type,
  Expression body,
  Expression? fallback,
});

/// [node]'s [LetShape], or `null` when it is not one.
///
/// A switch qualifies with a null arm, `null => d` or a trailing `_ => d`,
/// and a value arm binding the non-null value: `final v?`, or a
/// plain `final v` once the null arm has matched null first, or `final T v`
/// when `T` is just the target's own type made non-nullable, which is the
/// same check. A conditional qualifies when it compares a local variable or
/// parameter with null and the branch for the non-null case mentions it.
LetShape? letShapeOf(Expression node, TypeSystem typeSystem) => switch (node) {
  SwitchExpression() => _switchShape(node, typeSystem),
  ConditionalExpression() => _conditionalShape(node),
  _ => null,
};

LetShape? _switchShape(SwitchExpression node, TypeSystem typeSystem) {
  final target = node.expression;
  final (value, nothing, nullFirst) = switch (node.cases) {
    [final value, final nothing] when _isNullArm(nothing, wildcardOk: true) => (
      value,
      nothing,
      false,
    ),
    [final nothing, final value] when _isNullArm(nothing, wildcardOk: false) =>
      (value, nothing, true),
    _ => (null, null, false),
  };
  if (value == null ||
      nothing == null ||
      value.guardedPattern.whenClause != null) {
    return null;
  }
  final variable = switch (value.guardedPattern.pattern) {
    NullCheckPattern(pattern: final DeclaredVariablePattern variable) =>
      variable,
    final DeclaredVariablePattern variable
        when _onlyBinds(
          variable,
          target,
          nullFirst: nullFirst,
          typeSystem: typeSystem,
        ) =>
      variable,
    _ => null,
  };
  if (variable == null) {
    return null;
  }
  return (
    target: target,
    variable: variable.name.lexeme,
    type: variable.type,
    body: value.expression,
    fallback: nothing.expression is NullLiteral ? null : nothing.expression,
  );
}

/// Whether a value arm `final v` or `final T v`, with no `?`, still only
/// binds [target]'s non-null value: untyped once the null arm has matched
/// null first ([nullFirst]), or typed with [target]'s own type made
/// non-nullable, which is the same check.
bool _onlyBinds(
  DeclaredVariablePattern variable,
  Expression target, {
  required bool nullFirst,
  required TypeSystem typeSystem,
}) {
  if (nullFirst && variable.type == null) {
    return true;
  }
  final declared = variable.type?.type;
  final actual = target.staticType;
  return declared != null &&
      actual != null &&
      declared == typeSystem.promoteToNonNull(actual);
}

bool _isNullArm(SwitchExpressionCase arm, {required bool wildcardOk}) =>
    arm.guardedPattern.whenClause == null &&
    switch (arm.guardedPattern.pattern) {
      ConstantPattern(expression: NullLiteral()) => true,
      WildcardPattern(type: null) => wildcardOk,
      _ => false,
    };

LetShape? _conditionalShape(ConditionalExpression node) {
  final (variable, equalsNull) = switch (node.condition) {
    BinaryExpression(
      leftOperand: final SimpleIdentifier variable,
      rightOperand: NullLiteral(),
      :final operator,
    ) ||
    BinaryExpression(
      leftOperand: NullLiteral(),
      rightOperand: final SimpleIdentifier variable,
      :final operator,
    ) when _isLocal(variable) => (
      variable,
      switch (operator.type) {
        TokenType.EQ_EQ => true,
        TokenType.BANG_EQ => false,
        _ => null,
      },
    ),
    _ => (null, null),
  };
  if (variable == null || equalsNull == null) {
    return null;
  }
  final (whenNull, whenNotNull) = equalsNull
      ? (node.thenExpression, node.elseExpression)
      : (node.elseExpression, node.thenExpression);
  if (_mentions(whenNotNull, variable.name) == 0) {
    return null;
  }
  return (
    target: variable,
    variable: variable.name,
    type: null,
    body: whenNotNull,
    fallback: whenNull is NullLiteral ? null : whenNull,
  );
}

/// Whether [identifier] names something a null check promotes: a local
/// variable or a parameter.
bool _isLocal(SimpleIdentifier identifier) => switch (identifier.element) {
  LocalVariableElement() || FormalParameterElement() => true,
  _ => false,
};

/// How many times [node] mentions a simple identifier called [name].
int _mentions(AstNode node, String name) {
  var count = 0;
  node.visitChildren(
    _Counter((identifier) {
      if (identifier.name == name) {
        count++;
      }
    }),
  );
  if (node case SimpleIdentifier(name: final found) when found == name) {
    count++;
  }
  return count;
}

class _Counter(final void Function(SimpleIdentifier) onIdentifier)
    extends RecursiveAstVisitor<void> {
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) => onIdentifier(node);
}

/// What a [LetShape] becomes: the `code` to write, a `sketch` of it for
/// messages, with a lambda body and a fallback elided, and whether it uses
/// `let`.
typedef Rewrite = ({String code, String sketch, bool usesLet});

/// The shortest equivalent of [shape], with [text] giving a node's source: a
/// null-aware chain when the body only selects from the variable, `?.let`
/// with a tear-off when it only calls a function on it, `?.let` with a
/// lambda otherwise; `?? fallback` appended when the null case had a value.
Rewrite rewriteOf(LetShape shape, String Function(AstNode node) text) {
  final target = shape.target;
  final receiver = target.precedence < Precedence.postfix
      ? '(${text(target)})'
      : text(target);
  final body = shape.body;
  final String code;
  final String sketch;
  final bool usesLet;
  if (_chainRoot(body) case final root?
      when root.name == shape.variable &&
          _mentions(body, shape.variable) == 1) {
    code = root == body
        ? receiver
        : '$receiver?${text(body).substring(root.length)}';
    sketch = code;
    usesLet = false;
  } else if (_tearOff(body, shape.variable, text) case final function?) {
    code = '$receiver?.let($function)';
    sketch = code;
    usesLet = true;
  } else {
    final parameter = switch (shape.type) {
      final type? => '${text(type)} ${shape.variable}',
      null => shape.variable,
    };
    code = '$receiver?.let(($parameter) => ${text(body)})';
    sketch = '$receiver?.let(($parameter) => …)';
    usesLet = true;
  }
  final fallback = shape.fallback;
  if (fallback == null) {
    return (code: code, sketch: sketch, usesLet: usesLet);
  }
  final fallbackCode = fallback.precedence < Precedence.ifNull
      ? '(${text(fallback)})'
      : text(fallback);
  return (
    code: '$code ?? $fallbackCode',
    sketch: '$sketch ?? …',
    usesLet: usesLet,
  );
}

/// The identifier [body] selects from when it is one selector chain,
/// `v.a.b(c)`, `v[0]`, `v.a!.b`, or `v` itself: the chain's root, which a
/// `?` after the receiver turns null-aware. The first selector has to be a
/// `.` or an index, since `?` cannot precede `!` or another `?.`.
SimpleIdentifier? _chainRoot(Expression body) => switch (body) {
  final SimpleIdentifier root => root,
  PrefixedIdentifier(prefix: final root) => root,
  PropertyAccess(
    target: final SimpleIdentifier root,
    operator: Token(type: TokenType.PERIOD),
  ) =>
    root,
  PropertyAccess(
    target: final target?,
    isCascaded: false,
    operator: Token(type: TokenType.PERIOD || TokenType.QUESTION_PERIOD),
  )
      when target is! SimpleIdentifier =>
    _chainRoot(target),
  MethodInvocation(
    target: final SimpleIdentifier root,
    operator: Token(type: TokenType.PERIOD),
  ) =>
    root,
  MethodInvocation(
    target: final target?,
    isCascaded: false,
    operator: Token(type: TokenType.PERIOD || TokenType.QUESTION_PERIOD),
  )
      when target is! SimpleIdentifier =>
    _chainRoot(target),
  IndexExpression(
    target: final SimpleIdentifier root,
    question: null,
    isCascaded: false,
  ) =>
    root,
  IndexExpression(target: final target?, isCascaded: false)
      when target is! SimpleIdentifier =>
    _chainRoot(target),
  PostfixExpression(operator: Token(type: TokenType.BANG), :final operand)
      when operand is! SimpleIdentifier =>
    _chainRoot(operand),
  _ => null,
};

/// The function [body] calls with the [variable] as its only argument,
/// `int.parse(v)` or `f(v)`, as a tear-off; `null` for any other body.
String? _tearOff(
  Expression body,
  String variable,
  String Function(AstNode node) text,
) {
  if (body
      case MethodInvocation(
        typeArguments: null,
        isCascaded: false,
        argumentList: ArgumentList(
          arguments: [SimpleIdentifier(name: final argument)],
        ),
        :final target,
        :final methodName,
      )
      when argument == variable) {
    return switch (target) {
      null => methodName.name,
      Identifier(element: InterfaceElement() || PrefixElement()) =>
        '${text(target)}.${methodName.name}',
      _ => null,
    };
  }
  return null;
}

/// Applies [rewriteOf] to the flagged expression, importing the extension
/// when `let` is used and the file lacks it.
class ReplaceWithLet({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.replaceWithLet',
    DartFixKindPriority.standard,
    "Replace with '{0}'",
  );

  static final _extensions = Uri.parse('package:ciach/src/extensions.dart');

  late final _rewrite = rewriteOf(
    letShapeOf(node as Expression, typeSystem)!,
    (node) => getRangeText(range.node(node)),
  );

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [_rewrite.sketch];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    await builder.addDartFileEdit(file, (builder) {
      if (_rewrite.usesLet) {
        builder.importLibrary(_extensions);
      }
      builder.addSimpleReplacement(range.node(node), _rewrite.code);
    });
  }
}
