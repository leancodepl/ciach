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
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:ciach_lints/src/guard_tests.dart';

/// Flags a `when` clause that tests a variable of its own pattern in a way
/// that the pattern can: `v is T`, `v != null`, and a comparison of `v` with
/// a constant `c`, such as `v > c`. `v == c`, a `bool` `v` and `!v` are
/// flagged when nothing else reads `v`. `CLAUDE.md` wants these tests in the
/// pattern: `final T v`, `final v?`, `final v && > c`, `c`, `true`.
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
/// make: the [moves] that put them in the pattern, the [moved] operands of
/// the clause, and the [rest] of its `&&` operands.
class GuardRewrite._({
  required final GuardedPattern guarded,
  required final List<_Move> moves,
  required final List<Expression> moved,
  required final List<Expression> rest,
  required final String content,
}) {
  /// The rewrite of [guarded] in [content], the file's text, or `null` when
  /// its `when` clause makes no test that the pattern can make. It moves
  /// every test that applying the fix again and again would move.
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
    final testsByVariable = <DeclaredVariablePattern, List<GuardTest>>{};
    for (final operand in operands) {
      final test = guardTestOf(operand);
      if ((test, variables.declarations[test?.variable.element]) case (
        final test?,
        final declaration?,
      )) {
        (testsByVariable[declaration] ??= []).add(test);
      }
    }
    final moves = testsByVariable.entries
        .map((entry) => _Move.of(entry.key, entry.value, scope, content))
        .nonNulls
        .toList();
    if (moves.isEmpty) {
      return null;
    }
    final moved = {for (final move in moves) ...move.operands};
    return GuardRewrite._(
      guarded: guarded,
      moves: moves,
      moved: operands.where(moved.contains).toList(),
      rest: operands.where((operand) => !moved.contains(operand)).toList(),
      content: content,
    );
  }

  /// The moved tests, quoted, for the message: `'v is T' and 'w != null'`.
  String get movedTests =>
      moved.map((operand) => "'${_sourceOf(operand, content)}'").join(' and ');

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

/// The tests on the variable of [declaration] that move into it: the
/// [operands] that made them leave the `when` clause, the [type] that the
/// variable gets, whether it gets a null check, and the [valueTests] whose
/// patterns join it or, when they [replaced] it, stand in its place.
final class _Move._({
  required final DeclaredVariablePattern declaration,
  required final List<Expression> operands,
  required final TypeAnnotation? type,
  required final bool nullChecked,
  required final List<ValueTest> valueTests,
  required final bool replaced,
  required final String content,
}) {
  /// The move of [tests], the tests on the variable of [declaration], or
  /// `null` when none of them can move. [scope] is the node in which the
  /// variable can be read, and [content] is the file's text.
  ///
  /// Moving a test can let a test before it move, as a pinned value can
  /// replace the variable once nothing else reads it, so the tests are tried
  /// in order until a pass moves none.
  static _Move? of(
    DeclaredVariablePattern declaration,
    List<GuardTest> tests,
    AstNode scope,
    String content,
  ) {
    final typeSystem = _libraryOf(declaration).typeSystem;
    var type = declaration.type;
    var nullChecked = false;
    final valueTests = <ValueTest>[];
    var replaced = false;
    final moved = <Expression>[];
    var moving = true;
    while (moving) {
      moving = false;
      for (final test in tests) {
        if (moved.contains(test.operand)) {
          continue;
        }
        final readElsewhere = _readsOutside(scope, test.variable, [
          ...moved,
          test.operand,
        ]);
        switch (test) {
          case TypeTest(type: final tested)
              when _narrows(tested, type, typeSystem):
            type = tested;
          case NullTest():
            nullChecked = true;
          case ValueTest(pinsValue: false) when readElsewhere:
            valueTests.add(test);
          case ValueTest() when !readElsewhere:
            valueTests.add(test);
            replaced = true;
          case TypeTest() || ValueTest():
            continue;
        }
        moved.add(test.operand);
        moving = true;
      }
    }
    if (moved.isEmpty) {
      return null;
    }
    return _Move._(
      declaration: declaration,
      operands: moved,
      type: type,
      nullChecked: nullChecked,
      valueTests: valueTests,
      replaced: replaced,
      content: content,
    );
  }

  /// The rewrite of the declaration, with the null check or cast around it.
  late final _Edit edit = () {
    final library = _libraryOf(declaration);
    // Once a test has replaced the variable, the patterns stand in the
    // variable's place, in the order in which they moved.
    final patterns = valueTests.map((test) => test.pattern);
    // Patterns that replace a typed variable keep its type, as
    // `int() && > 0`, unless the matched value has that type already or
    // every pattern pins a value of that type.
    final keepsType =
        replaced &&
        switch ((type?.type, declaration.matchedValueType)) {
          (final typed?, final matched?) =>
            !library.typeSystem.isSubtypeOf(matched, typed) &&
                !valueTests.every((test) => _pinsValueOf(test, typed, library)),
          _ => false,
        };
    final core = switch ((replaced, type)) {
      (true, final type?) when keepsType => [
        '${_sourceOf(type, content)}()',
        ...patterns,
      ].join(' && '),
      (true, _) => patterns.join(' && '),
      (false, final type?) when type != declaration.type => _typed(
        declaration,
        _sourceOf(type, content),
      ),
      (false, _) => _sourceOf(declaration, content),
    };
    // A non-nullable type already rules out `null`.
    final excludesNull =
        (!replaced || keepsType) &&
        switch (type?.type) {
          final typed? => library.typeSystem.isNonNullable(typed),
          null => false,
        };
    final nullCheck = nullChecked && !excludesNull;
    final bound = _withUnaryPatterns(declaration);
    final grouped = replaced && (nullCheck || bound != declaration)
        ? '($core)'
        : core;
    final before = content.substring(bound.offset, declaration.offset);
    final after = content.substring(declaration.end, bound.end);
    final rewritten = [
      '$before${nullCheck ? '$grouped?' : grouped}$after',
      if (!replaced) ...patterns,
    ].join(' && ');
    // A shorthand field, `:final v`, needs its name once its pattern is more
    // than the variable and the null check or cast around it.
    return switch (bound.parent) {
      PatternField(name: PatternFieldName(name: null)) && final field
          when valueTests.isNotEmpty =>
        _Edit(range.node(field), '${declaration.name.lexeme}: $rewritten'),
      _ => _Edit(range.node(bound), rewritten),
    };
  }();
}

/// The library of [declaration]. `_PatternVariables` keeps only the
/// declarations that have an element, and a local variable is in one
/// library.
LibraryElement _libraryOf(DeclaredVariablePattern declaration) =>
    declaration.declaredFragment!.element.library!;

/// Whether [tested] can replace [declared], the type that a variable has:
/// when the variable has none, or [tested] is a subtype of it.
bool _narrows(
  TypeAnnotation tested,
  TypeAnnotation? declared,
  TypeSystem typeSystem,
) => switch ((tested.type, declared)) {
  (_, null) => true,
  (final testedType?, TypeAnnotation(type: final declaredType?)) =>
    typeSystem.isSubtypeOf(testedType, declaredType),
  _ => false,
};

/// Whether [test] pins a value of [type] that isn't a number, so that every
/// value that it matches has [type]. A pinned `3` matches `3.0` too.
bool _pinsValueOf(ValueTest test, DartType type, LibraryElement library) =>
    switch (test.pinnedType) {
      final pinned? =>
        library.typeSystem.isSubtypeOf(pinned, type) &&
            !library.typeSystem.isSubtypeOf(
              pinned,
              library.typeProvider.numType,
            ),
      null => false,
    };

/// [declaration] with [type] as its type: `final T v` for `final v`, and
/// `T v` for `var v`.
String _typed(DeclaredVariablePattern declaration, String type) =>
    switch (declaration.keyword?.keyword) {
      Keyword.FINAL => 'final $type ${declaration.name.lexeme}',
      _ => '$type ${declaration.name.lexeme}',
    };

/// [pattern] with the cast, null-check and null-assert patterns that apply
/// to it: `final v?` for the `final v` in it.
DartPattern _withUnaryPatterns(DartPattern pattern) => switch (pattern.parent) {
  (CastPattern() || NullCheckPattern() || NullAssertPattern()) &&
      final DartPattern parent =>
    _withUnaryPatterns(parent),
  _ => pattern,
};

/// Whether [scope] reads the variable of [variable] outside every one of
/// [operands].
bool _readsOutside(
  AstNode scope,
  SimpleIdentifier variable,
  List<AstNode> operands,
) {
  final reads = _Reads(variable.element, outside: operands);
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

/// Finds whether a node reads [element] outside every node in [outside].
class _Reads(final Element? element, {required final List<AstNode> outside})
    extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == element &&
        outside.every(
          (operand) => node.end <= operand.offset || node.offset >= operand.end,
        )) {
      found = true;
    }
  }
}
