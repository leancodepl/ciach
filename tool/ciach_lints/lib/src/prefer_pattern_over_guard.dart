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
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a `when` clause that tests a variable of its own pattern in a way
/// that the pattern can: `v is T`, `v != null`, and a comparison of `v` with
/// a constant `c`, such as `v > c`. `v == c`, a `bool` `v` and `!v` are
/// flagged when nothing else reads `v`. `CLAUDE.md` wants these tests in the
/// pattern: `final T v`, `final v?`, `> c && final v`, `c`, `true`.
///
/// A test of one of `v`'s members, as in `when v.isNotEmpty`, is not
/// flagged: `CLAUDE.md` prefers `case final v when v.isNotEmpty` to an object
/// pattern that only reads that member.
class PreferPatternOverGuard() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_pattern_over_guard',
    "This 'when' clause tests {0}, which the pattern can test itself.",
    correctionMessage: "Try replacing the pattern and its guard with '{1}'.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addGuardedPattern(this, _Visitor(this, context));
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitGuardedPattern(GuardedPattern node) {
    if ((node.whenClause, context.currentUnit) case (
      final whenClause?,
      final unit?,
    )) {
      if (GuardRewrite.of(node, unit.content) case final rewrite?) {
        rule.reportAtNode(
          whenClause,
          arguments: [rewrite.movedTests, rewrite.replacement],
        );
      }
    }
  }
}

/// Moves the tests that the flagged `when` clause makes into its pattern.
class MoveGuardIntoPattern({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.moveGuardIntoPattern',
    DartFixKindPriority.standard,
    "Replace with '{0}'",
  );

  late final _rewrite = switch (node.parent) {
    final GuardedPattern guarded => GuardRewrite.of(
      guarded,
      unitResult.content,
    ),
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_rewrite?.replacement];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_rewrite case final rewrite?) {
      await builder.addDartFileEdit(
        file,
        (builder) => builder.addSimpleReplacement(
          range.node(rewrite.guarded),
          rewrite.replacement,
        ),
      );
    }
  }
}

/// A [guarded] pattern whose `when` clause makes tests that the pattern can
/// make: the [moves] that put them in the pattern, and the [rest] of the
/// clause's `&&` operands.
class GuardRewrite._({
  required final GuardedPattern guarded,
  required final List<_Move> moves,
  required final List<Expression> rest,
  required final String content,
}) {
  /// The rewrite of [guarded] in [content], the file's text, or `null` when
  /// its `when` clause makes no test that the pattern can make.
  static GuardRewrite? of(GuardedPattern guarded, String content) {
    final whenClause = guarded.whenClause;
    if (whenClause == null) {
      return null;
    }
    final variables = _PatternVariables();
    guarded.pattern.accept(variables);
    final scope =
        guarded.thisOrAncestorMatching(
          (node) =>
              node is SwitchExpression ||
              node is SwitchStatement ||
              node is IfStatement ||
              node is IfElement,
        ) ??
        guarded;
    final operands = _andOperands(whenClause.expression).toList();
    final moves = <_Move>[];
    for (final operand in operands) {
      final test = _testOf(operand);
      final declaration = variables.declarations[test?.variable.element];
      if ((test, declaration) case (final test?, final declaration?)
          when !moves.any((move) => move.declaration == declaration)) {
        if (_Move.of(operand, test, declaration, scope, content)
            case final move?) {
          moves.add(move);
        }
      }
    }
    if (moves.isEmpty) {
      return null;
    }
    final moved = {for (final move in moves) move.operand};
    return GuardRewrite._(
      guarded: guarded,
      moves: moves,
      rest: operands.where((operand) => !moved.contains(operand)).toList(),
      content: content,
    );
  }

  /// The moved tests, quoted, for the message: `'v is T' and 'w != null'`.
  String get movedTests => moves
      .map((move) => "'${_sourceOf(move.operand, content)}'")
      .join(' and ');

  /// The source of the rewritten pattern and what remains of its `when`
  /// clause.
  late final String replacement = () {
    final pattern = guarded.pattern;
    final edits = moves.map((move) => move.edit).toList()
      ..sort((a, b) => a.range.offset.compareTo(b.range.offset));
    final pieces = <String>[];
    var cursor = pattern.offset;
    for (final edit in edits) {
      pieces
        ..add(content.substring(cursor, edit.range.offset))
        ..add(edit.code);
      cursor = edit.range.end;
    }
    pieces.add(content.substring(cursor, pattern.end));
    final source = pieces.join();
    return rest.isEmpty
        ? source
        : '$source when '
              '${rest.map((operand) => _sourceOf(operand, content)).join(' && ')}';
  }();
}

/// The test that an operand of a `when` clause makes on a [variable].
sealed class _Test(final SimpleIdentifier variable);

/// `variable is type`.
final class _TypeTest(super.variable, final TypeAnnotation type) extends _Test;

/// `variable != null`.
final class _NullTest(super.variable) extends _Test;

/// A test that the [pattern] makes, such as `> 0` or `true`. It
/// [pinsValue] when the pattern matches one value only, so that the
/// variable is redundant.
final class _ValueTest(
  super.variable,
  final String pattern, {
  required final bool pinsValue,
}) extends _Test;

/// Relational operators and the operators they become when their operands
/// swap places: `0 < v` is `v > 0`.
const _swapped = {
  '==': '==',
  '!=': '!=',
  '<': '>',
  '<=': '>=',
  '>': '<',
  '>=': '<=',
};

/// The test that [operand] makes on one variable, or `null` when it makes
/// none that a pattern can make.
_Test? _testOf(Expression operand) => switch (operand) {
  IsExpression(
    expression: final SimpleIdentifier variable,
    notOperator: null,
    :final type,
  ) =>
    _TypeTest(variable, type),
  BinaryExpression(
    operator: Token(type: .BANG_EQ),
    leftOperand: final SimpleIdentifier variable,
    rightOperand: NullLiteral(),
  ) ||
  BinaryExpression(
    operator: Token(type: .BANG_EQ),
    leftOperand: NullLiteral(),
    rightOperand: final SimpleIdentifier variable,
  ) => _NullTest(variable),
  BinaryExpression(
    :final operator,
    leftOperand: final SimpleIdentifier variable,
    :final rightOperand,
  )
      when _swapped.containsKey(operator.lexeme) && _isConstant(rightOperand) =>
    _comparison(variable, operator.lexeme, rightOperand),
  BinaryExpression(
    :final operator,
    :final leftOperand,
    rightOperand: final SimpleIdentifier variable,
  )
      when _swapped.containsKey(operator.lexeme) && _isConstant(leftOperand) =>
    _comparison(variable, _swapped[operator.lexeme]!, leftOperand),
  SimpleIdentifier(:final staticType) when _isBool(staticType) => _ValueTest(
    operand,
    'true',
    pinsValue: true,
  ),
  PrefixExpression(
    operator: Token(type: .BANG),
    operand: final SimpleIdentifier variable,
  )
      when _isBool(variable.staticType) =>
    _ValueTest(variable, 'false', pinsValue: true),
  _ => null,
};

/// The test `variable <operator> constant`.
_ValueTest _comparison(
  SimpleIdentifier variable,
  String operator,
  Expression constant,
) => switch (operator) {
  '==' => _ValueTest(variable, constant.toSource(), pinsValue: true),
  _ => _ValueTest(
    variable,
    '$operator ${constant.toSource()}',
    pinsValue: false,
  ),
};

/// Whether [type] is `bool`, not `bool?`.
bool _isBool(DartType? type) =>
    type != null &&
    type.isDartCoreBool &&
    type.nullabilitySuffix == NullabilitySuffix.none;

/// Whether [expression] can be a constant pattern: a literal, a negated
/// number, or the name of a constant.
bool _isConstant(Expression expression) => switch (expression) {
  BooleanLiteral() ||
  IntegerLiteral() ||
  DoubleLiteral() ||
  NullLiteral() ||
  SimpleStringLiteral() => true,
  PrefixExpression(
    operator: Token(type: .MINUS),
    operand: IntegerLiteral() || DoubleLiteral(),
  ) =>
    true,
  SimpleIdentifier(:final element) ||
  PrefixedIdentifier(:final element) ||
  PropertyAccess(
    target: Identifier(),
    propertyName: SimpleIdentifier(:final element),
  ) ||
  DotShorthandPropertyAccess(
    propertyName: SimpleIdentifier(:final element),
  ) => switch (element) {
    PropertyAccessorElement(:final variable) => variable.isConst,
    VariableElement(:final isConst) => isConst,
    _ => false,
  },
  _ => false,
};

/// The operands of [expression] joined by `&&`, or [expression] itself.
Iterable<Expression> _andOperands(Expression expression) sync* {
  if (expression case BinaryExpression(
    operator: Token(type: .AMPERSAND_AMPERSAND),
    :final leftOperand,
    :final rightOperand,
  )) {
    yield* _andOperands(leftOperand);
    yield* _andOperands(rightOperand);
  } else {
    yield expression;
  }
}

/// A replacement of the source in [range] with [code].
final class _Edit(final SourceRange range, final String code);

/// The move of the test that an [operand] of a `when` clause makes on the
/// variable of [declaration] into the pattern: [edit] rewrites the
/// declaration.
final class _Move({
  required final Expression operand,
  required final DeclaredVariablePattern declaration,
  required final _Edit edit,
}) {
  /// The move of [test], made by [operand], into [declaration], or `null`
  /// when [test] pins the variable's value and [scope] reads the variable
  /// somewhere else. [content] is the file's text.
  static _Move? of(
    Expression operand,
    _Test test,
    DeclaredVariablePattern declaration,
    AstNode scope,
    String content,
  ) {
    final declared = _sourceOf(declaration, content);
    final readElsewhere = _readsOutside(scope, test.variable, operand);
    final code = switch (test) {
      _TypeTest(:final type) => _typed(declaration, _sourceOf(type, content)),
      _NullTest() => '$declared?',
      _ValueTest(pinsValue: true) when readElsewhere => null,
      _ValueTest(:final pattern) when readElsewhere => _grouped(
        '$pattern && $declared',
        declaration,
      ),
      _ValueTest(:final pattern) => _grouped(pattern, declaration),
    };
    if (code == null) {
      return null;
    }
    // A shorthand field, `:final v`, needs its name once its pattern is no
    // longer just the variable.
    final edit = switch ((test, declaration.parent)) {
      (_ValueTest(), final PatternField field) when field.name?.name == null =>
        _Edit(range.node(field), '${declaration.name.lexeme}: $code'),
      _ => _Edit(range.node(declaration), code),
    };
    return _Move(operand: operand, declaration: declaration, edit: edit);
  }
}

/// [declaration] with [type] as its type: `final T v` for `final v`, and
/// `T v` for `var v`.
String _typed(DeclaredVariablePattern declaration, String type) =>
    switch (declaration.keyword?.keyword) {
      Keyword.FINAL => 'final $type ${declaration.name.lexeme}',
      _ => '$type ${declaration.name.lexeme}',
    };

/// [code] in parentheses when it replaces a [declaration] that a cast or
/// null-check pattern applies to, which binds tighter than `&&`.
String _grouped(String code, DeclaredVariablePattern declaration) =>
    switch (declaration.parent) {
      CastPattern() || NullCheckPattern() || NullAssertPattern() => '($code)',
      _ => code,
    };

/// Whether [scope] reads the variable of [variable] outside [operand].
bool _readsOutside(AstNode scope, SimpleIdentifier variable, AstNode operand) {
  final reads = _Reads(variable.element, outside: operand);
  scope.accept(reads);
  return reads.found;
}

/// The source of [node] in [content], the file's text.
String _sourceOf(AstNode node, String content) =>
    content.substring(node.offset, node.end);

/// Collects the variables that a pattern declares.
class _PatternVariables() extends RecursiveAstVisitor<void> {
  final declarations = <Element, DeclaredVariablePattern>{};

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (node.declaredFragment?.element case final element?) {
      declarations[element] = node;
    }
    super.visitDeclaredVariablePattern(node);
  }
}

/// Finds whether a node reads [element] outside the node [outside].
class _Reads(final Element? element, {required final AstNode outside})
    extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element &&
        (node.offset < outside.offset || node.end > outside.end)) {
      found = true;
    }
  }
}
