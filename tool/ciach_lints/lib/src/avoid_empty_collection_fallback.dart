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
import 'package:analyzer/error/error.dart';
import 'package:analyzer/source/source_range.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:ciach_lints/src/promotion.dart';

/// Flags `xs ?? const []` and other empty collection fallbacks that only
/// skip a null collection: as the iterable of a `for` loop, in a spread, or
/// as the target of a call. `CLAUDE.md` wants `if (xs != null)` around the
/// loop when the check promotes `xs`, `if (xs case final xs?)` when it
/// doesn't, `...?xs`, or a null-aware call with the fallback at the end of
/// the chain, as in `xs?.map(f) ?? const []`.
class AvoidEmptyCollectionFallback() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'avoid_empty_collection_fallback',
    "This '??' falls back to an empty collection only to skip a null value.",
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
    registry.addBinaryExpression(this, _Visitor(this));
  }
}

class _Visitor(final AnalysisRule rule) extends SimpleAstVisitor<void> {
  @override
  void visitBinaryExpression(BinaryExpression node) {
    if (EmptyFallback.of(node) case final fallback?) {
      rule.reportAtNode(fallback.expression, arguments: [fallback.advice]);
    }
  }
}

/// Rewrites a loop over `xs ?? const []` into a loop inside `if (xs != null)`
/// or `if (xs case final xs?)`, and `...(xs ?? [])` into `...?xs`.
class SkipNullCollection({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.skipNullCollection',
    DartFixKindPriority.standard,
    '{0}',
  );

  late final _fallback = switch (node) {
    final Expression expression => EmptyFallback.of(expression.unParenthesized),
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_fallback?.fixTitle];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_fallback?.rewrite(utils.getLinePrefix, getRangeText)
        case (:final range, :final code)?) {
      await builder.addDartFileEdit(
        file,
        (builder) => builder.addSimpleReplacement(range, code),
      );
    }
  }
}

/// Where an empty collection fallback is used.
enum FallbackUse() {
  /// As the iterable of a `for` statement.
  loopStatement,

  /// As the iterable of a `for` element in a collection literal.
  loopElement,

  /// In a spread: `...(xs ?? [])`.
  spread,

  /// As the target of a method call or property access.
  target,
}

/// An `xs ?? <empty collection>` [expression], with any parentheses around
/// it, that only skips a null `xs`, the [left] operand.
class EmptyFallback({
  required final Expression expression,
  required final Expression left,
  required final FallbackUse use,
}) {
  /// The fallback that [node] is, or `null` when it is no such `??`.
  static EmptyFallback? of(Expression node) {
    if (node case BinaryExpression(
      operator: Token(type: .QUESTION_QUESTION),
      :final leftOperand,
      rightOperand: ListLiteral(elements: []) || SetOrMapLiteral(elements: []),
    )) {
      final expression = _outermostParentheses(node);
      final use = switch (expression.parent) {
        ForEachParts(:final iterable, parent: ForStatement())
            when iterable == expression =>
          FallbackUse.loopStatement,
        ForEachParts(:final iterable, parent: ForElement())
            when iterable == expression =>
          FallbackUse.loopElement,
        SpreadElement(isNullAware: false) => FallbackUse.spread,
        MethodInvocation(:final target) || PropertyAccess(:final target)
            when target == expression =>
          FallbackUse.target,
        _ => null,
      };
      if (use != null) {
        return EmptyFallback(
          expression: expression,
          left: leftOperand,
          use: use,
        );
      }
    }
    return null;
  }

  /// The name that `if (… case final name?)` binds: the last name in [left]
  /// without its leading underscores, as `items` for `widget.items` and
  /// `widget._items`.
  late final String? _name = switch (left) {
    SimpleIdentifier(:final name) ||
    PrefixedIdentifier(identifier: SimpleIdentifier(:final name)) ||
    PropertyAccess(
      propertyName: SimpleIdentifier(:final name),
    ) => _nameAfterUnderscores.firstMatch(name)?.namedGroup('name'),
    _ => null,
  };

  /// What to write instead, for the correction message.
  String get advice => switch ((use, _promotes, _name)) {
    (.loopStatement || .loopElement, true, _) =>
      "an 'if (${left.toSource()} != null)' around the loop",
    (.loopStatement || .loopElement, false, final name?) =>
      "an 'if (${left.toSource()} case final $name?)' around the loop",
    (.loopStatement || .loopElement, false, null) =>
      "an 'if (… case final name?)' around the loop",
    (.spread, _, _) => "'...?${left.toSource()}'",
    (.target, _, _) =>
      "a null-aware call on '${left.toSource()}', with the fallback at the end of the chain",
  };

  /// The title of the fix, or `null` when it can't rewrite this fallback.
  String? get fixTitle => switch ((use, _guard)) {
    (.loopStatement || .loopElement, final guard?) =>
      "Wrap the loop in 'if (${guard.condition(left.toSource())})'",
    (.spread, _) => "Replace with '...?${left.toSource()}'",
    _ => null,
  };

  /// Whether `left != null` promotes [left], so that the loop can read
  /// [left] itself.
  late final bool _promotes = isPromotable(left, expression);

  /// The `if` that the fix puts around the loop, or `null` when it can't
  /// put one there: a null check when the check promotes [left], or else an
  /// if-case that binds [_name], unless the loop already uses that name.
  late final _Guard? _guard = switch ((use, _enclosing, _name)) {
    (.spread || .target, _, _) || (_, null, _) => null,
    (_, final loop?, _) when loop.parent is LabeledStatement => null,
    _ when _promotes => _NullCheck(),
    (_, final loop?, final name?) when !_clashes(loop, name) => _IfCase(name),
    _ => null,
  };

  /// The `for` statement, `for` element or spread that [expression] is in,
  /// or `null` when [expression] is the target of a call.
  late final AstNode? _enclosing = switch (use) {
    .loopStatement || .loopElement => expression.parent?.parent,
    .spread => expression.parent,
    .target => null,
  };

  /// Whether [loop] uses [name] outside [left], so that binding [name] around
  /// the loop would change what the loop reads. That includes a loop over
  /// `xs ?? []` that reads `xs`: the fix binds only a value that a null check
  /// can't promote, and the loop may change that value.
  bool _clashes(AstNode loop, String name) {
    final uses = _NameUses(name, skip: left);
    loop.accept(uses);
    return uses.found;
  }

  /// The replacement that the fix makes, or `null` when it can't make one.
  /// [linePrefix] gives the whitespace before an offset's line, and
  /// [textOf] the source of a range.
  ({SourceRange range, String code})? rewrite(
    String Function(int offset) linePrefix,
    String Function(SourceRange range) textOf,
  ) {
    final leftSource = textOf(range.node(left));
    return switch ((use, _enclosing, _guard)) {
      (.spread, final spread?, _) => (
        range: range.node(spread),
        code: '...?$leftSource',
      ),
      (.loopElement, final loop?, final guard?) => (
        range: range.node(loop),
        code:
            'if (${guard.condition(leftSource)}) '
            '${_loopWith(loop, guard.iterable(leftSource), textOf)}',
      ),
      (.loopStatement, final loop?, final guard?) => (
        range: range.node(loop),
        code: _wrapped(
          loop,
          guard,
          leftSource,
          linePrefix(loop.offset),
          textOf,
        ),
      ),
      _ => null,
    };
  }

  /// The source of [loop] with [iterable] as its iterable.
  String _loopWith(
    AstNode loop,
    String iterable,
    String Function(SourceRange range) textOf,
  ) =>
      '${textOf(range.startStart(loop, expression))}$iterable'
      '${textOf(range.endEnd(expression, loop))}';

  /// [loop] inside the `if` of [guard], with its lines indented one step
  /// more, except those that start inside a multi-line string.
  String _wrapped(
    AstNode loop,
    _Guard guard,
    String leftSource,
    String indent,
    String Function(SourceRange range) textOf,
  ) {
    final strings = _MultilineStrings();
    loop.accept(strings);
    final before = _indented(
      textOf(range.startStart(loop, expression)),
      loop.offset,
      strings.ranges,
    );
    final after = _indented(
      textOf(range.endEnd(expression, loop)),
      expression.end,
      strings.ranges,
    );
    return 'if (${guard.condition(leftSource)}) {\n'
        '$indent  $before${guard.iterable(leftSource)}$after\n'
        '$indent}';
  }

  /// [text], which starts at [start] in the file, with each line after its
  /// first indented by two spaces, unless the line is empty or starts inside
  /// one of [strings].
  static String _indented(String text, int start, List<SourceRange> strings) {
    final lines = text.split('\n');
    var lineStart = start;
    final indented = <String>[];
    for (final (i, line) in lines.indexed) {
      final keep =
          i == 0 ||
          line.isEmpty ||
          strings.any(
            (string) => string.offset < lineStart && lineStart < string.end,
          );
      indented.add(keep ? line : '  $line');
      lineStart += line.length + 1;
    }
    return indented.join('\n');
  }

  /// [node] with every pair of parentheses that encloses only it.
  static Expression _outermostParentheses(Expression node) =>
      switch (node.parent) {
        final ParenthesizedExpression parent => _outermostParentheses(parent),
        _ => node,
      };
}

/// Finds whether a node declares, reads or assigns a name outside [skip].
class _NameUses(final String name, {required final AstNode skip})
    extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name && !_inSkip(node)) {
      found = true;
    }
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    if (node.name.lexeme == name) {
      found = true;
    }
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (node.name.lexeme == name) {
      found = true;
    }
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) {
      found = true;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (node.name.lexeme == name) {
      found = true;
    }
    super.visitAssignedVariablePattern(node);
  }

  bool _inSkip(AstNode node) =>
      node.offset >= skip.offset && node.end <= skip.end;
}

/// Matches a name that has a character other than `_`. Its `name` group holds
/// the name without its leading underscores, as `items` for `_items`.
final _nameAfterUnderscores = RegExp('^_*(?<name>[^_].*)');

/// Collects the ranges of the multi-line string literals in a node.
class _MultilineStrings() extends RecursiveAstVisitor<void> {
  final ranges = <SourceRange>[];

  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) {
    if (node.isMultiline) {
      ranges.add(range.node(node));
    }
  }

  @override
  void visitStringInterpolation(StringInterpolation node) {
    if (node.isMultiline) {
      ranges.add(range.node(node));
    }
    super.visitStringInterpolation(node);
  }
}

/// The `if` that the fix puts around a loop.
sealed class _Guard() {
  /// The test of the `if`, for the source [left] of the checked value.
  String condition(String left);

  /// What the loop iterates inside the `if`.
  String iterable(String left);
}

/// `if (xs != null)`, for an `xs` that the check promotes.
final class _NullCheck() extends _Guard {
  @override
  String condition(String left) => '$left != null';

  @override
  String iterable(String left) => left;
}

/// `if (xs case final name?)`, which binds the checked value to [name].
final class _IfCase(final String name) extends _Guard {
  @override
  String condition(String left) => '$left case final $name?';

  @override
  String iterable(String left) => name;
}
