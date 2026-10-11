import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/precedence.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a switch expression that only maps null to null,
/// `switch (x) { final v? => f(v), null => null }`, which `x?.let(f)` from
/// `lib/src/extensions.dart` says in one call.
class PreferLet() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_let',
    "This switch only maps null to null; '?.let' says the same in one call.",
    correctionMessage: "Try replacing the switch with '?.let((value) => …)'.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addSwitchExpression(this, _Visitor(this));
  }
}

class _Visitor(final AnalysisRule rule) extends SimpleAstVisitor<void> {
  @override
  void visitSwitchExpression(SwitchExpression node) {
    if (letShapeOf(node) != null) {
      rule.reportAtNode(node);
    }
  }
}

/// The parts of a `switch (x) { final v? => body, null => null }` that
/// `x?.let((v) => body)` keeps: the bound `variable` and the `body`.
typedef LetShape = ({DeclaredVariablePattern variable, Expression body});

/// [node]'s [LetShape], or `null` when it is not one. The null arm may come
/// first, after which the value arm needs no `?`; a wildcard arm counts as the
/// null arm only when it comes second, since first it would match everything.
LetShape? letShapeOf(SwitchExpression node) => switch (node.cases) {
  [final value, final nothing] when _isNullArm(nothing, wildcardOk: true) =>
    _valueArm(value, checked: true),
  [final nothing, final value] when _isNullArm(nothing, wildcardOk: false) =>
    _valueArm(value, checked: false),
  _ => null,
};

/// [arm] as a value arm: `final v? => body`, or also `final v => body` when
/// not [checked], after a null arm already matched null.
LetShape? _valueArm(SwitchExpressionCase arm, {required bool checked}) =>
    switch (arm.guardedPattern) {
      GuardedPattern(
        whenClause: null,
        pattern: NullCheckPattern(
          pattern: final DeclaredVariablePattern variable,
        ),
      ) =>
        (variable: variable, body: arm.expression),
      GuardedPattern(
        whenClause: null,
        pattern: final DeclaredVariablePattern variable,
      )
          when !checked =>
        (variable: variable, body: arm.expression),
      _ => null,
    };

bool _isNullArm(SwitchExpressionCase arm, {required bool wildcardOk}) =>
    arm.expression is NullLiteral &&
    arm.guardedPattern.whenClause == null &&
    switch (arm.guardedPattern.pattern) {
      ConstantPattern(expression: NullLiteral()) => true,
      WildcardPattern(type: null) => wildcardOk,
      _ => false,
    };

/// Rewrites the flagged switch into `x?.let((v) => body)`, importing the
/// extension when the file lacks it.
class ReplaceWithLet({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.replaceWithLet',
    DartFixKindPriority.standard,
    "Replace with '?.let'",
  );

  static final _extensions = Uri.parse('package:ciach/src/extensions.dart');

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  Future<void> compute(ChangeBuilder builder) async {
    final switchExpression = node;
    if (switchExpression is! SwitchExpression) {
      return;
    }
    final shape = letShapeOf(switchExpression);
    if (shape == null) {
      return;
    }
    final target = switchExpression.expression;
    final receiver = target.precedence < Precedence.postfix
        ? '(${_text(target)})'
        : _text(target);
    final variable = shape.variable;
    final parameter = switch (variable.type) {
      final type? => '${_text(type)} ${variable.name.lexeme}',
      null => variable.name.lexeme,
    };
    await builder.addDartFileEdit(file, (builder) {
      builder
        ..importLibrary(_extensions)
        ..addSimpleReplacement(
          range.node(switchExpression),
          '$receiver?.let(($parameter) => ${_text(shape.body)})',
        );
    });
  }

  String _text(AstNode node) => getRangeText(range.node(node));
}
