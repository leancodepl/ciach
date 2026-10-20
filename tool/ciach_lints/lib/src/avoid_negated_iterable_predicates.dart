/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a negated `any`, `every` or `none` on an `Iterable`, and a call of
/// `any`, `every`, `none`, `where` or `whereNot` whose predicate negates its
/// result, when another of these methods says the same with fewer negations:
/// `xs.none(f)` for `!xs.any(f)`, `xs.whereNot(f)` for
/// `xs.where((x) => !f(x))`, `!xs.every(f)` for `xs.any((x) => !f(x))`.
/// `none` and `whereNot` come from `package:collection`.
class AvoidNegatedIterablePredicates() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'avoid_negated_iterable_predicates',
    "'{0}' says the same with fewer negations.",
    correctionMessage: "Try replacing it with '{0}'.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addPrefixExpression(this, visitor)
      ..addMethodInvocation(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitPrefixExpression(PrefixExpression node) => _check(node);

  @override
  void visitMethodInvocation(MethodInvocation node) => _check(node);

  void _check(Expression node) {
    if (context.currentUnit case final unit?) {
      if (NegationRewrite.of(
            node,
            context.typeSystem,
            context.typeProvider,
            unit.content,
          )
          case final rewrite?) {
        rule.reportAtNode(node, arguments: [rewrite.code]);
      }
    }
  }
}

/// Replaces the flagged call with the one that has fewer negations.
class RemoveNegation({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.removeNegation',
    DartFixKindPriority.standard,
    "Replace with '{0}'",
  );

  static final _collection = Uri.parse('package:collection/collection.dart');

  late final _rewrite = switch (node) {
    final Expression expression => NegationRewrite.of(
      expression,
      typeSystem,
      typeProvider,
      unitResult.content,
    ),
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_rewrite?.code];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_rewrite case final rewrite?) {
      await builder.addDartFileEdit(file, (builder) {
        if (rewrite.needsCollection) {
          builder.importLibrary(_collection);
        }
        builder.addSimpleReplacement(range.node(node), rewrite.code);
      });
    }
  }
}

/// The [code] that says what a flagged call says with fewer negations, and
/// whether it [needsCollection] for `none` or `whereNot`.
class NegationRewrite._({
  required final String code,
  required final bool needsCollection,
}) {
  /// The rewrite of [node], a `!` before a call or a call, or `null` when it
  /// has no negation to remove. [content] is the file's text.
  static NegationRewrite? of(
    Expression node,
    TypeSystem typeSystem,
    TypeProvider typeProvider,
    String content,
  ) {
    final (negated, call) = switch (node) {
      PrefixExpression(operator: Token(type: .BANG), :final operand) => (
        true,
        operand.unParenthesized,
      ),
      // A call under a `!` is rewritten together with the `!`.
      MethodInvocation() when _negationOf(node) == null => (false, node),
      _ => (false, null),
    };
    if (call is! MethodInvocation || call.typeArguments != null) {
      return null;
    }
    final MethodInvocation(:target, :methodName, :operator, :argumentList) =
        call;
    final targetType = target?.staticType;
    if (target == null ||
        targetType == null ||
        !typeSystem.isSubtypeOf(
          typeSystem.promoteToNonNull(targetType),
          typeProvider.iterableDynamicType,
        )) {
      return null;
    }
    if (argumentList.arguments case [final Expression argument]) {
      final predicate = _NegatedPredicate.of(argument, content);
      final rewritten = _rewritten(
        methodName.name,
        negated: negated,
        predicateNegated: predicate != null,
      );
      if (rewritten == null) {
        return null;
      }
      final (:method, :negate) = rewritten;
      final argumentCode = predicate?.code ?? _sourceOf(argument, content);
      final callCode =
          '${_sourceOf(target, content)}${operator?.lexeme ?? '.'}$method($argumentCode)';
      final code = switch ((negate, negated)) {
        (true, false) when _isTarget(node) => '(!$callCode)',
        (true, _) => '!$callCode',
        (false, _) => callCode,
      };
      return ._(
        code: code,
        needsCollection: method == 'none' || method == 'whereNot',
      );
    }
    return null;
  }
}

/// The `!` that applies to [node], through any parentheses, or `null`.
PrefixExpression? _negationOf(Expression node) => switch (node.parent) {
  final ParenthesizedExpression parent => _negationOf(parent),
  final PrefixExpression parent when parent.operator.type == .BANG => parent,
  _ => null,
};

/// Whether [node] is the target of a call, an access or an index, where a
/// `!` before it would apply to the whole expression.
bool _isTarget(Expression node) => switch (node.parent) {
  MethodInvocation(:final target) ||
  PropertyAccess(:final target) ||
  IndexExpression(:final target) => target == node,
  PostfixExpression() || FunctionExpressionInvocation() => true,
  _ => false,
};

/// The method that says what `[negated] xs.method(p)` says, with `p`
/// negated when [predicateNegated], and whether it is negated itself; `null`
/// when no method says it with fewer negations.
({String method, bool negate})? _rewritten(
  String method, {
  required bool negated,
  required bool predicateNegated,
}) => switch ((method, negated, predicateNegated)) {
  ('any', true, false) => (method: 'none', negate: false),
  ('none', true, false) => (method: 'any', negate: false),
  ('any', false, true) => (method: 'every', negate: true),
  ('every', false, true) => (method: 'none', negate: false),
  ('none', false, true) ||
  ('any', true, true) => (method: 'every', negate: false),
  ('every', true, true) => (method: 'any', negate: false),
  ('none', true, true) => (method: 'every', negate: true),
  ('where', false, true) => (method: 'whereNot', negate: false),
  ('whereNot', false, true) => (method: 'where', negate: false),
  _ => null,
};

/// A predicate `(x) => !e`, and the [code] of `(x) => e` or, when `e` only
/// passes `x` to a method of a plain receiver, the tear-off of that method.
final class _NegatedPredicate._(final String code) {
  /// The predicate that [argument] is, or `null` when it is no `(x) => !e`.
  static _NegatedPredicate? of(Expression argument, String content) {
    if (argument case FunctionExpression(
      typeParameters: null,
      parameters: FormalParameterList(
            parameters: [
              RegularFormalParameter(
                :final name?,
                isRequiredPositional: true,
                functionTypedSuffix: null,
              ),
            ],
          ) &&
          final parameters,
      body: ExpressionFunctionBody(
        expression: PrefixExpression(
          operator: Token(type: .BANG),
          :final operand,
        ),
      ),
    )) {
      return ._(switch (operand) {
        MethodInvocation(
          typeArguments: null,
          argumentList: ArgumentList(
            arguments: [SimpleIdentifier(name: final argument)],
          ),
          :final target,
          :final methodName,
          operator: Token(type: .PERIOD) || null,
        )
            when argument == name.lexeme &&
                _isPlainReceiver(target, argument) =>
          target == null
              ? methodName.name
              : '${_sourceOf(target, content)}.${methodName.name}',
        _ =>
          '${_sourceOf(parameters, content)} => ${_sourceOf(operand, content)}',
      });
    }
    return null;
  }
}

/// Whether a tear-off from [target] evaluates the same as calling through it
/// each time: [target] is absent, `this` or a chain of names, none of them
/// [parameter].
bool _isPlainReceiver(Expression? target, String parameter) => switch (target) {
  null || ThisExpression() => true,
  SimpleIdentifier(:final name) => name != parameter,
  PrefixedIdentifier(:final prefix, :final identifier) =>
    prefix.name != parameter && identifier.name != parameter,
  PropertyAccess(:final target, operator: Token(type: .PERIOD)) =>
    _isPlainReceiver(target, parameter),
  _ => false,
};

/// The source of [node] in [content], the file's text.
String _sourceOf(AstNode node, String content) =>
    content.substring(node.offset, node.end);
