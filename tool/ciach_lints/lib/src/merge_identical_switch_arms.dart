/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:math';

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags switch arms that have the same body, which `CLAUDE.md` wants as one
/// arm whose patterns are joined with `||`. When `_` or `default`, which
/// matches every value, has the same body, the other arms are redundant
/// instead.
///
/// The arms have no `when` clause and bind the same variables with the same
/// types, as a `||` pattern requires. An arm that other arms separate from
/// the rest of its group moves past them only when its constant patterns
/// share no value with theirs and no empty case falls into it, so that every
/// value still reaches the same body. The second arm of each group is flagged.
class MergeIdenticalSwitchArms() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'merge_identical_switch_arms',
    'This arm has the same body as an earlier arm.',
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
    for (final group in ArmGroup.allIn(node)) {
      rule.reportAtNode(group.arms[1].node, arguments: [group.advice]);
    }
  }
}

/// Merges the group of arms whose second arm is flagged.
class MergeSwitchArms({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.mergeSwitchArms',
    DartFixKindPriority.standard,
    '{0}',
  );

  late final _group = switch (node.thisOrAncestorMatching(
    (node) => node is SwitchExpression || node is SwitchStatement,
  )) {
    final AstNode switchNode => ArmGroup.allIn(
      switchNode,
    ).where((group) => group.arms[1].node == node).firstOrNull,
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_group?.fixTitle];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_group case final group?) {
      await builder.addDartFileEdit(file, (builder) {
        for (final edit in group.edits) {
          builder.addSimpleReplacement(edit.range, edit.code);
        }
      });
    }
  }
}

/// A variable that a pattern binds.
typedef _Variable = ({String name, DartType type, bool isFinal});

/// The [index]th arm of a switch expression or member of a switch statement:
/// its [pattern], or `null` for `default`, and the lexemes of its [body]. It
/// [canMerge] when nothing but its pattern and body sets it apart.
final class _Arm({
  required final AstNode node,
  required final int index,
  required final DartPattern? pattern,
  required final bool canMerge,
  required final List<String> body,
}) {
  /// The arms of [node], a switch expression or statement.
  static List<_Arm> allIn(AstNode node) => switch (node) {
    SwitchExpression(:final cases) => [
      for (final (index, arm) in cases.indexed)
        _Arm(
          node: arm,
          index: index,
          pattern: arm.guardedPattern.pattern,
          canMerge: arm.guardedPattern.whenClause == null,
          body: _lexemes(
            arm.expression.beginToken,
            arm.expression.endToken,
          ).toList(),
        ),
    ],
    SwitchStatement(:final members) => [
      for (final (index, member) in members.indexed)
        _Arm(
          node: member,
          index: index,
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

  /// The keys of the values that [pattern] matches, or `null` when they
  /// aren't known: see [_constantsOf].
  late final Set<Object?>? constants = _constantsOf(pattern);

  /// Whether no value matches both this arm and [other], which is `false`
  /// when the values that either matches aren't known.
  bool isDisjointFrom(_Arm other) => switch ((constants, other.constants)) {
    (final mine?, final theirs?) => mine.intersection(theirs).isEmpty,
    _ => false,
  };

  /// Whether this arm and [later], an arm after it, could be one arm if no
  /// arm were between them. Only the last arm of a group can be `default`.
  bool mergesWith(_Arm later) =>
      canMerge &&
      later.canMerge &&
      pattern != null &&
      body.isNotEmpty &&
      body.length == later.body.length &&
      Iterable<int>.generate(body.length)
          .every((i) => body[i] == later.body[i]) &&
      variables.length == later.variables.length &&
      variables.containsAll(later.variables);
}

/// Arms with the same body that can be one arm. When the last of [arms]
/// matches every value, the others are redundant; otherwise the first arm
/// takes the patterns of the others. [all] holds every arm of the switch.
final class ArmGroup._(final List<_Arm> arms, final List<_Arm> all) {
  /// The groups of arms in [node], a switch expression or statement.
  static Iterable<ArmGroup> allIn(AstNode node) sync* {
    final all = _Arm.allIn(node);
    final grouped = <_Arm>{};
    // The arms that a catch-all covers leave the switch, so they are grouped
    // before any of them could join another arm.
    if (all.indexWhere((arm) => arm.matchesAll) case final last && >= 0) {
      final covered = <_Arm>[];
      for (final arm in all.take(last).toList().reversed) {
        if (arm.mergesWith(all[last]) &&
            _canMove(
              all,
              arm,
              all[last],
              stays: (between) => !covered.contains(between),
            )) {
          covered.add(arm);
        }
      }
      if (covered.isNotEmpty) {
        final arms = [...covered.reversed, all[last]];
        grouped.addAll(arms);
        yield ArmGroup._(arms, all);
      }
    }
    // `_` or `default` joins no group here: it could join only an arm that it
    // covers, which the group above holds already.
    for (final first in all) {
      if (grouped.contains(first)) {
        continue;
      }
      final arms = [first];
      for (final arm in all.skip(first.index + 1)) {
        if (!grouped.contains(arm) &&
            first.mergesWith(arm) &&
            _canMove(
              all,
              arm,
              first,
              stays: (between) => !arms.contains(between),
            )) {
          arms.add(arm);
        }
      }
      if (arms.length > 1) {
        grouped.addAll(arms);
        yield ArmGroup._(arms, all);
      }
    }
  }

  /// Whether [arm] can move next to [target], past the arms between them that
  /// [stays] holds for: either none, or [arm] has no value in common with any
  /// of them and no empty case falls into it.
  static bool _canMove(
    List<_Arm> all,
    _Arm arm,
    _Arm target, {
    required bool Function(_Arm between) stays,
  }) {
    final passed = all
        .sublist(min(arm.index, target.index) + 1, max(arm.index, target.index))
        .where(stays);
    return passed.isEmpty ||
        ((arm.index == 0 || all[arm.index - 1].body.isNotEmpty) &&
            passed.every(arm.isDisjointFrom));
  }

  /// Whether the last arm matches every value, so that the others are
  /// redundant.
  bool get _endsWithCatchAll => arms.last.matchesAll;

  /// The joined patterns, quoted, for the messages: `'A || B'`.
  String get _joined =>
      "'${arms.map((arm) => arm.pattern?.toSource() ?? 'default').join(' || ')}'";

  /// What to do, for the correction message.
  String get advice => _endsWithCatchAll
      ? 'removing the arms that the last arm covers'
      : 'joining the patterns into $_joined';

  /// The title of the fix.
  String get fixTitle => _endsWithCatchAll
      ? 'Remove the arms that the last arm covers'
      : 'Join the patterns into $_joined';

  /// The edits that merge the group.
  Iterable<({SourceRange range, String code})> get edits sync* {
    if (_endsWithCatchAll) {
      for (final block in _blocks(arms.take(arms.length - 1))) {
        yield (range: _removal(block), code: '');
      }
      return;
    }
    // The arms right after the first one join it where they are, and the
    // others leave their place and add their patterns to the last of those.
    final neighbors = _blocks(arms).first;
    for (final (i, arm) in neighbors.indexed.skip(1)) {
      // Every arm but the last of a group has a pattern, and this group has
      // no `default`, which is only ever last.
      yield (
        range: range.endStart(neighbors[i - 1].pattern!, arm.pattern!),
        code: ' || ',
      );
    }
    final apart = arms.skip(neighbors.length).toList();
    if (apart.isNotEmpty) {
      yield (
        range: SourceRange(neighbors.last.pattern!.end, 0),
        code: apart.map((arm) => ' || ${arm.pattern!.toSource()}').join(),
      );
      for (final block in _blocks(apart)) {
        yield (range: _removal(block), code: '');
      }
    }
  }

  /// [arms] split where they aren't next to each other in the switch.
  static List<List<_Arm>> _blocks(Iterable<_Arm> arms) => arms.fold(
    [],
    (blocks, arm) => switch (blocks) {
      [..., [..., final last] && final block]
          when last.index + 1 == arm.index =>
        blocks..last = [...block, arm],
      _ => blocks..add([arm]),
    },
  );

  /// The range that removes [block], arms next to each other, and one
  /// separator from the switch. It starts at the end of the arm before
  /// [block], so that the ranges of neighboring blocks don't overlap. A block
  /// that starts the switch is removed up to the start of the next arm, which
  /// stays: only a group that ends with `_` or `default` removes the first
  /// arms of a switch, and they are all in one of its blocks.
  SourceRange _removal(List<_Arm> block) => switch (block.first.index) {
    0 => range.startStart(block.first.node, all[block.last.index + 1].node),
    final first => range.endEnd(all[first - 1].node, block.last.node),
  };
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

/// The keys of the values that [pattern] matches when it is a constant
/// pattern, or `||` of them, whose values are numbers, strings, `bool`s,
/// `null` or enum values: written as literals or named constants. An enum
/// value's key is its type and index, and the key of any other value is the
/// value: a set holds `1` and `1.0`, or `0` and `-0.0`, as one element,
/// since they are equal and have the same hash code. `null` when the values
/// aren't known.
Set<Object?>? _constantsOf(DartPattern? pattern) => switch (pattern) {
  ConstantPattern(:final expression) => switch (_keyOf(expression)) {
    (:final key)? => {key},
    null => null,
  },
  LogicalOrPattern(:final leftOperand, :final rightOperand) => switch ((
    _constantsOf(leftOperand),
    _constantsOf(rightOperand),
  )) {
    (final left?, final right?) => {...left, ...right},
    _ => null,
  },
  ParenthesizedPattern(:final pattern) => _constantsOf(pattern),
  _ => null,
};

/// The key of the value of [expression], or `null` when it isn't known.
({Object? key})? _keyOf(Expression expression) => switch (expression) {
  IntegerLiteral(:final value?) => (key: value),
  DoubleLiteral(:final value) => (key: value),
  PrefixExpression(operator: Token(type: .MINUS), :final operand) =>
    switch (_keyOf(operand)) {
      (key: final num number) => (key: -number),
      _ => null,
    },
  SimpleStringLiteral(:final value) => (key: value),
  BooleanLiteral(:final value) => (key: value),
  NullLiteral() => (key: null),
  SimpleIdentifier(:final element) ||
  PrefixedIdentifier(:final element) ||
  PropertyAccess(propertyName: SimpleIdentifier(:final element)) ||
  DotShorthandPropertyAccess(
    propertyName: SimpleIdentifier(:final element),
  ) => switch (element) {
    GetterElement(variable: final VariableElement variable) ||
    (final VariableElement variable) => switch (variable
        .computeConstantValue()) {
      final value? => _keyOfValue(value),
      null => null,
    },
    _ => null,
  },
  _ => null,
};

/// The key of [value], a constant's value, or `null` when it isn't a number,
/// a string, a `bool`, `null` or an enum value.
({Object? key})? _keyOfValue(DartObject value) => switch ((
  value.type,
  value.toIntValue(),
  value.toDoubleValue(),
  value.toStringValue(),
  value.toBoolValue(),
)) {
  (InterfaceType(element: final EnumElement type), _, _, _, _) => switch (value
      .getField('index')
      ?.toIntValue()) {
    final index? => (key: (type: type, index: index)),
    null => null,
  },
  (_, final int number?, _, _, _) => (key: number),
  (_, _, final double number?, _, _) => (key: number),
  (_, _, _, final String text?, _) => (key: text),
  (_, _, _, _, final bool flag?) => (key: flag),
  _ when value.isNull => (key: null),
  _ => null,
};
