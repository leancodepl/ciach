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
import 'package:collection/collection.dart';

/// Flags an expression that only checks a value for null before using it:
/// `switch (x) { final v? => f(v), null => d }`, `x == null ? null : f(x)`,
/// `x == null ? d : f(x)`, and `a.b == null ? d : f(a.b!)` for a value a null
/// check cannot promote. A null-aware chain (`x?.length`) or `x?.let(f)` from
/// ciach's `lib/src/util/extensions.dart`, with `?? d` for a fallback other
/// than `null`, says the same in one expression. A rewrite to `let` is
/// reported only in a package that can import that library.
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
    final visitor = _Visitor(
      this,
      context.typeSystem,
      canImportLet:
          context.libraryElement?.session.uriConverter.uriToPath(_extensions) !=
          null,
    );
    registry
      ..addSwitchExpression(this, visitor)
      ..addConditionalExpression(this, visitor);
  }
}

class _Visitor(
  final AnalysisRule rule,
  final TypeSystem typeSystem, {
  required final bool canImportLet,
}) extends SimpleAstVisitor<void> {
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
    if (rewrite.usesLet && !canImportLet) {
      return;
    }
    rule.reportAtNode(node, arguments: [kind, rewrite.sketch]);
  }
}

/// What a null-aware chain or `x?.let(f)` can replace: the `target` checked
/// against null, the name and, when spelled, the type of the `variable` bound
/// to its non-null value, the `body` computed from that, the `aliases` in the
/// body that stand for the variable (each `target!` when the target is not
/// promotable), and the `fallback` produced for null when it is not `null`
/// itself.
class const LetShape({
  required final Expression target,
  required final String variable,
  required final TypeAnnotation? type,
  required final Expression body,
  required final List<Expression> aliases,
  required final Expression? fallback,
});

/// [node]'s [LetShape], or `null` when it is not one.
///
/// A switch qualifies with a null arm, `null => d` or a trailing `_ => d`,
/// and a value arm binding the non-null value: `final v?`, or a
/// plain `final v` once the null arm has matched null first, or `final T v`
/// when `T` is just the target's own type made non-nullable, which is the
/// same check. A conditional qualifies when it compares a local variable or
/// parameter with null and the branch for the non-null case mentions it, or
/// compares any other expression with null and that branch reads it, as
/// `expression` or `expression!`.
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
  return .new(
    target: target,
    variable: variable.name.lexeme,
    type: variable.type,
    body: value.expression,
    aliases: const [],
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
  final (target, equalsNull) = switch (node.condition) {
    BinaryExpression(
      leftOperand: final target,
      rightOperand: NullLiteral(),
      :final operator,
    ) ||
    BinaryExpression(
      leftOperand: NullLiteral(),
      rightOperand: final target,
      :final operator,
    ) => (
      target,
      switch (operator.type) {
        TokenType.EQ_EQ => true,
        TokenType.BANG_EQ => false,
        _ => null,
      },
    ),
    _ => (null, null),
  };
  if (target == null || equalsNull == null) {
    return null;
  }
  final (whenNull, whenNotNull) = equalsNull
      ? (node.thenExpression, node.elseExpression)
      : (node.elseExpression, node.thenExpression);
  final fallback = whenNull is NullLiteral ? null : whenNull;
  if (target case SimpleIdentifier(:final name) when _isLocal(target)) {
    if (_identifiersNamed(whenNotNull, name) == 0) {
      return null;
    }
    return .new(
      target: target,
      variable: name,
      type: null,
      body: whenNotNull,
      aliases: const [],
      fallback: fallback,
    );
  }
  // The check promotes nothing, so the branch reads the value as `target!` or
  // as `target` again; each of those becomes the variable, named after the
  // target unless the branch already mentions that name.
  final uses = _Uses(target.toSource());
  whenNotNull.accept(uses);
  if (uses.aliases.isEmpty || uses.assigned) {
    return null;
  }
  final variable = [?_lastName(target), 'it'].firstWhereOrNull(
    (name) => _identifiersNamed(whenNotNull, name, aliases: uses.aliases) == 0,
  );
  if (variable == null) {
    return null;
  }
  return .new(
    target: target,
    variable: variable,
    type: null,
    body: whenNotNull,
    aliases: uses.aliases,
    fallback: fallback,
  );
}

/// Whether [identifier] names something a null check promotes: a local
/// variable or a parameter.
bool _isLocal(SimpleIdentifier identifier) => switch (identifier.element) {
  LocalVariableElement() || FormalParameterElement() => true,
  _ => false,
};

/// The identifier [expression] ends with, as a name for its value: `foo` for
/// `a.foo`, `a.foo()` or `a.foo[0]`.
String? _lastName(Expression expression) => switch (expression) {
  SimpleIdentifier(:final name) ||
  PrefixedIdentifier(identifier: SimpleIdentifier(:final name)) ||
  PropertyAccess(propertyName: SimpleIdentifier(:final name)) ||
  MethodInvocation(methodName: SimpleIdentifier(:final name)) => name,
  IndexExpression(:final target?) => _lastName(target),
  PostfixExpression(:final operand) => _lastName(operand),
  ParenthesizedExpression(:final expression) => _lastName(expression),
  _ => null,
};

/// How a branch uses a value spelled [source] that a null check cannot
/// promote: the [aliases] are its occurrences, as `source!` or bare, each to
/// become the variable; [assigned] says one of them is written to, which the
/// variable could not stand in for.
class _Uses(final String source) extends GeneralizingAstVisitor<void> {
  final List<Expression> aliases = [];
  bool assigned = false;

  @override
  void visitPostfixExpression(PostfixExpression node) {
    if (node.operator.type == TokenType.BANG &&
        node.operand.toSource() == source) {
      aliases.add(node);
      return;
    }
    super.visitPostfixExpression(node);
  }

  @override
  void visitExpression(Expression node) {
    if (node.toSource() == source) {
      aliases.add(node);
      if (node.parent case AssignmentExpression(leftHandSide: final written)
          when written == node) {
        assigned = true;
      }
      return;
    }
    super.visitExpression(node);
  }
}

/// How many simple identifiers in [node], itself included, are called
/// [name], outside the [aliases].
int _identifiersNamed(
  AstNode node,
  String name, {
  List<Expression> aliases = const [],
}) {
  final counter = _Counter(name, aliases);
  node.accept(counter);
  return counter.count;
}

/// How many times the body of a [LetShape] mentions its variable: as an
/// identifier called [name], or through one of the [aliases].
int _mentions(AstNode body, String name, List<Expression> aliases) =>
    _identifiersNamed(body, name, aliases: aliases) + aliases.length;

class _Counter(final String name, final List<Expression> aliases)
    extends GeneralizingAstVisitor<void> {
  int count = 0;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name && !aliases.contains(node)) {
      count++;
    }
    super.visitSimpleIdentifier(node);
  }

  @override
  void visitNode(AstNode node) {
    if (node is! Expression || !aliases.contains(node)) {
      super.visitNode(node);
    }
  }
}

/// What a [LetShape] becomes: the `code` to write, a `sketch` of it for
/// messages, with a lambda body and a fallback elided, and whether it uses
/// `let`.
class const Rewrite({
  required final String code,
  required final String sketch,
  required final bool usesLet,
});

/// The shortest equivalent of [shape], with [text] giving a node's source: a
/// null-aware chain when the body only selects from the variable, `?.let`
/// with a tear-off when it only calls a function on it, `?.let` with a
/// lambda otherwise; `?? fallback` appended when the null case had a value.
Rewrite rewriteOf(LetShape shape, String Function(AstNode node) text) {
  final LetShape(:target, :variable, :type, :body, :aliases, :fallback) = shape;
  final receiver = target.precedence < Precedence.postfix
      ? '(${text(target)})'
      : text(target);
  final String code;
  final String sketch;
  final bool usesLet;
  if (_chainRoot(body, aliases) case final root?
      when (root is! SimpleIdentifier || root.name == variable) &&
          _mentions(body, variable, aliases) == 1) {
    code = root == body
        ? receiver
        : '$receiver?${text(body).substring(root.length)}';
    sketch = code;
    usesLet = false;
  } else if (_tearOff(body, variable, aliases, text) case final function?) {
    code = '$receiver?.let($function)';
    sketch = code;
    usesLet = true;
  } else {
    final parameter = switch (type) {
      final type? => '${text(type)} $variable',
      null => variable,
    };
    final bodyText = _withAliasesNamed(body, aliases, variable, text);
    code = '$receiver?.let(($parameter) => $bodyText)';
    sketch = '$receiver?.let(($parameter) => …)';
    usesLet = true;
  }
  if (fallback == null) {
    return .new(code: code, sketch: sketch, usesLet: usesLet);
  }
  final fallbackCode = fallback.precedence < Precedence.ifNull
      ? '(${text(fallback)})'
      : text(fallback);
  return .new(
    code: '$code ?? $fallbackCode',
    sketch: '$sketch ?? …',
    usesLet: usesLet,
  );
}

/// [body]'s source with each of the [aliases] replaced by [variable]. Only
/// exact source, as [text] gives the fix, keeps the offsets; the normalized
/// source the rule sketches with does not, and there the body is elided
/// anyway.
String _withAliasesNamed(
  Expression body,
  List<Expression> aliases,
  String variable,
  String Function(AstNode node) text,
) {
  var source = text(body);
  if (aliases.isEmpty) {
    return source;
  }
  if (source.length != body.length) {
    return '…';
  }
  final byOffsetDescending = [...aliases]
    ..sort((a, b) => b.offset.compareTo(a.offset));
  for (final alias in byOffsetDescending) {
    final start = alias.offset - body.offset;
    source = source.replaceRange(start, start + alias.length, variable);
  }
  return source;
}

/// The expression [body] selects from when it is one selector chain,
/// `v.a.b(c)`, `v[0]`, `v.a!.b`, or `v` itself: the chain's root, a simple
/// identifier or one of the [aliases], which a `?` after the receiver turns
/// null-aware. The first selector has to be a `.` or an index, since `?`
/// cannot precede `!` or another `?.`.
Expression? _chainRoot(Expression body, List<Expression> aliases) {
  bool isRoot(Expression node) =>
      node is SimpleIdentifier || aliases.contains(node);
  if (isRoot(body)) {
    return body;
  }
  final (Expression? target, bool plainSelector) = switch (body) {
    PrefixedIdentifier(:final prefix) => (prefix, true),
    PropertyAccess(:final target?, isCascaded: false, :final operator) => (
      target,
      operator.type == TokenType.PERIOD,
    ),
    MethodInvocation(:final target?, isCascaded: false, :final operator) => (
      target,
      operator?.type == TokenType.PERIOD,
    ),
    IndexExpression(:final target?, isCascaded: false, :final question) => (
      target,
      question == null,
    ),
    PostfixExpression(operator: Token(type: TokenType.BANG), :final operand) =>
      (operand, false),
    _ => (null, false),
  };
  if (target == null) {
    return null;
  }
  if (isRoot(target)) {
    return plainSelector ? target : null;
  }
  return _chainRoot(target, aliases);
}

/// Whether [node] is the variable: an identifier called [variable], or one
/// of the [aliases].
bool _isVariable(Expression node, String variable, List<Expression> aliases) =>
    node is SimpleIdentifier && node.name == variable || aliases.contains(node);

/// The function [body] calls with the variable, called [variable] or one of
/// the [aliases], as its only argument, `int.parse(v)` or `f(v)`, as a
/// tear-off; `null` for any other body.
String? _tearOff(
  Expression body,
  String variable,
  List<Expression> aliases,
  String Function(AstNode node) text,
) => switch (body) {
  MethodInvocation(
    typeArguments: null,
    isCascaded: false,
    argumentList: ArgumentList(arguments: [final Expression argument]),
    :final target,
    :final methodName,
  )
      when _isVariable(argument, variable, aliases) =>
    switch (target) {
      null => methodName.name,
      Identifier(element: InterfaceElement() || PrefixElement()) =>
        '${text(target)}.${methodName.name}',
      _ => null,
    },
  _ => null,
};

/// The library that declares `let`.
final _extensions = Uri.parse('package:ciach/src/util/extensions.dart');

/// Applies [rewriteOf] to the flagged expression, importing the extension
/// when `let` is used and the file lacks it.
class ReplaceWithLet({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.replaceWithLet',
    DartFixKindPriority.standard,
    "Replace with '{0}'",
  );

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
