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
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a run of neighboring switch arms that have the same body, which
/// `CLAUDE.md` wants as one arm whose patterns are joined with `||`. When the
/// run ends with `_` or `default`, which matches everything the arms before
/// it match, those arms are redundant instead.
///
/// The arms of a run have no `when` clause and bind the same variables with
/// the same types, as a `||` pattern requires. The first arm that repeats a
/// body is flagged, once per run.
class MergeIdenticalSwitchArms() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'merge_identical_switch_arms',
    'This arm has the same body as the arm before it.',
    correctionMessage: 'Try {0}.',
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this);
    registry
      ..addSwitchExpression(this, visitor)
      ..addSwitchStatement(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule) extends SimpleAstVisitor<void> {
  @override
  void visitSwitchExpression(SwitchExpression node) => _report(node);

  @override
  void visitSwitchStatement(SwitchStatement node) => _report(node);

  void _report(AstNode node) {
    for (final run in ArmRun.allIn(node)) {
      rule.reportAtNode(run.arms[1].node, arguments: [run.advice]);
    }
  }
}

/// Merges the run of arms that starts before the flagged arm.
class MergeSwitchArms({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.mergeSwitchArms',
    DartFixKindPriority.standard,
    '{0}',
  );

  late final _run = switch (node.thisOrAncestorMatching(
    (node) => node is SwitchExpression || node is SwitchStatement,
  )) {
    final AstNode switchNode => ArmRun.allIn(
      switchNode,
    ).where((run) => run.arms[1].node == node).firstOrNull,
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_run?.fixTitle];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_run case final run?) {
      await builder.addDartFileEdit(file, (builder) {
        for (final edit in run.edits) {
          builder.addSimpleReplacement(edit.range, edit.code);
        }
      });
    }
  }
}

/// A variable that a pattern binds.
typedef _Variable = ({String name, DartType type, bool isFinal});

/// An arm of a switch expression or a member of a switch statement: its
/// [pattern], or `null` for `default`, and the lexemes of its [body]. It
/// [canMerge] when nothing but its pattern and body sets it apart.
final class _Arm({
  required final AstNode node,
  required final DartPattern? pattern,
  required final bool canMerge,
  required final List<String> body,
}) {
  /// The arms of [node], a switch expression or statement.
  static List<_Arm> allIn(AstNode node) => switch (node) {
    SwitchExpression(:final cases) => [
      for (final arm in cases)
        _Arm(
          node: arm,
          pattern: arm.guardedPattern.pattern,
          canMerge: arm.guardedPattern.whenClause == null,
          body: _lexemes(
            arm.expression.beginToken,
            arm.expression.endToken,
          ).toList(),
        ),
    ],
    SwitchStatement(:final members) => [
      for (final member in members)
        _Arm(
          node: member,
          pattern: switch (member) {
            SwitchPatternCase(:final guardedPattern) => guardedPattern.pattern,
            SwitchCase() || SwitchDefault() => null,
          },
          // A labeled member, and a constant case of a language version
          // before patterns, can't join a `||` pattern.
          canMerge:
              member.labels.isEmpty &&
              switch (member) {
                SwitchPatternCase(:final guardedPattern) =>
                  guardedPattern.whenClause == null,
                SwitchDefault() => true,
                SwitchCase() => false,
              },
          body: switch (member.statements) {
            [] => const [],
            [final first, ...] => _lexemes(
              first.beginToken,
              member.statements.last.endToken,
            ).toList(),
          },
        ),
    ],
    _ => const [],
  };

  /// Whether this arm matches every value: `_` or `default`.
  bool get matchesAll => switch ((node, pattern)) {
    (SwitchDefault(), _) || (_, WildcardPattern(type: null)) => true,
    _ => false,
  };

  /// The variables that [pattern] binds.
  late final Set<_Variable> variables = () {
    final collector = _Variables();
    pattern?.accept(collector);
    return collector.variables;
  }();

  /// Whether this arm and the [next] one can be one arm. Only the last arm
  /// of a run can be `default`.
  bool mergesWith(_Arm next) =>
      canMerge &&
      next.canMerge &&
      pattern != null &&
      body.isNotEmpty &&
      body.length == next.body.length &&
      Iterable<int>.generate(body.length)
          .every((i) => body[i] == next.body[i]) &&
      variables.length == next.variables.length &&
      variables.containsAll(next.variables);
}

/// A run of neighboring [arms] with the same body.
final class ArmRun._(final List<_Arm> arms) {
  /// The runs of arms in [node], a switch expression or statement.
  static Iterable<ArmRun> allIn(AstNode node) sync* {
    final arms = _Arm.allIn(node);
    var start = 0;
    for (var i = 1; i <= arms.length; i++) {
      if (i == arms.length || !arms[i - 1].mergesWith(arms[i])) {
        if (i - start >= 2) {
          yield ArmRun._(arms.sublist(start, i));
        }
        start = i;
      }
    }
  }

  /// Whether the last arm matches every value, so that the others are
  /// redundant.
  bool get _endsWithCatchAll => arms.last.matchesAll;

  /// The joined patterns, quoted, for the messages: `'A || B'`.
  String get _joined =>
      "'${arms.map((arm) => arm.pattern?.toSource() ?? 'default').join(' || ')}'";

  /// What to do, for the correction message.
  String get advice => _endsWithCatchAll
      ? 'removing the arms before the last one, which matches what they match'
      : 'joining the patterns into $_joined';

  /// The title of the fix.
  String get fixTitle => _endsWithCatchAll
      ? 'Remove the arms that the last arm covers'
      : 'Join the patterns into $_joined';

  /// The edits that merge the run.
  Iterable<({SourceRange range, String code})> get edits sync* {
    if (_endsWithCatchAll) {
      yield (
        range: range.startStart(arms.first.node, arms.last.node),
        code: '',
      );
    } else {
      for (final (i, arm) in arms.indexed.skip(1)) {
        // Every arm but the last of a run has a pattern, and this run has no
        // `default`, which is only ever last.
        yield (
          range: range.endStart(arms[i - 1].pattern!, arm.pattern!),
          code: ' || ',
        );
      }
    }
  }
}

/// The lexemes of the tokens from [first] to [last], which leave out
/// comments.
Iterable<String> _lexemes(Token first, Token last) sync* {
  for (var token = first; ; token = token.next!) {
    yield token.lexeme;
    if (token == last) {
      return;
    }
  }
}

/// Collects the variables that a pattern binds.
class _Variables() extends RecursiveAstVisitor<void> {
  final variables = <_Variable>{};

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (node.declaredFragment?.element case final element?) {
      variables.add((
        name: element.displayName,
        type: element.type,
        isFinal: element.isFinal,
      ));
    }
    super.visitDeclaredVariablePattern(node);
  }
}
