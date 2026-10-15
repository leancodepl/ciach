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

/// Flags `xs ?? const []` and other empty collection fallbacks that only
/// skip a null collection: as the iterable of a `for` loop, in a spread, or
/// as the target of a call. `CLAUDE.md` wants `if (xs case final xs?)` around
/// the loop, `...?xs`, or a null-aware call with the fallback at the end of
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

/// Rewrites a loop over `xs ?? const []` into a loop inside
/// `if (xs case final xs?)`, and `...(xs ?? [])` into `...?xs`.
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

  /// The name that `if (… case final name?)` binds: the last name in [left],
  /// as `items` for `widget.items`.
  late final String? _name = switch (left) {
    SimpleIdentifier(:final name) ||
    PrefixedIdentifier(identifier: SimpleIdentifier(:final name)) ||
    PropertyAccess(propertyName: SimpleIdentifier(:final name)) => name,
    _ => null,
  };

  /// What to write instead, for the correction message.
  String get advice => switch ((use, _name)) {
    (.loopStatement || .loopElement, final name?) =>
      "an 'if (${left.toSource()} case final $name?)' around the loop",
    (.loopStatement || .loopElement, null) =>
      "an 'if (… case final name?)' around the loop",
    (.spread, _) => "'...?${left.toSource()}'",
    (.target, _) =>
      "a null-aware call on '${left.toSource()}', with the fallback at the end of the chain",
  };

  /// The title of the fix, or `null` when it can't rewrite this fallback.
  String? get fixTitle => switch ((use, _loopName)) {
    (.loopStatement || .loopElement, final name?) =>
      "Wrap the loop in 'if (${left.toSource()} case final $name?)'",
    (.spread, _) => "Replace with '...?${left.toSource()}'",
    _ => null,
  };

  /// The name to bind around the loop, or `null` when there is none or
  /// binding it would change the loop.
  late final String? _loopName = switch ((_enclosing, _name)) {
    (final loop?, final name?)
        when loop.parent is! LabeledStatement && !_clashes(loop, name) =>
      name,
    _ => null,
  };

  /// The `for` statement, `for` element or spread that [expression] is in,
  /// or `null` when [expression] is the target of a call.
  late final AstNode? _enclosing = switch (use) {
    .loopStatement || .loopElement => expression.parent?.parent,
    .spread => expression.parent,
    .target => null,
  };

  /// Whether [loop] assigns [name], or reads it as something other than
  /// [left], so that binding [name] around the loop would change the loop.
  /// A loop over `xs ?? []` may read `xs`: the bound `xs` has the same value.
  bool _clashes(AstNode loop, String name) {
    final uses = _NameUses(name, skip: left);
    loop.accept(uses);
    return uses.assigned || (uses.read && left is! SimpleIdentifier);
  }

  /// The replacement that the fix makes, or `null` when it can't make one.
  /// [linePrefix] gives the whitespace before an offset's line, and
  /// [textOf] the source of a range.
  ({SourceRange range, String code})? rewrite(
    String Function(int offset) linePrefix,
    String Function(SourceRange range) textOf,
  ) {
    final leftSource = textOf(range.node(left));
    return switch ((use, _enclosing, _loopName)) {
      (.spread, final spread?, _) => (
        range: range.node(spread),
        code: '...?$leftSource',
      ),
      (.loopElement, final loop?, final name?) => (
        range: range.node(loop),
        code:
            'if ($leftSource case final $name?) '
            '${_loopWith(loop, name, textOf)}',
      ),
      (.loopStatement, final loop?, final name?) => (
        range: range.node(loop),
        code: _wrapped(loop, name, leftSource, linePrefix(loop.offset), textOf),
      ),
      _ => null,
    };
  }

  /// The source of [loop] with [name] as its iterable.
  String _loopWith(
    AstNode loop,
    String name,
    String Function(SourceRange range) textOf,
  ) =>
      '${textOf(range.startStart(loop, expression))}$name'
      '${textOf(range.endEnd(expression, loop))}';

  /// [loop] inside `if (… case final name?) { … }`, with its lines indented
  /// one step more, except those that start inside a multi-line string.
  String _wrapped(
    AstNode loop,
    String name,
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
    return 'if ($leftSource case final $name?) {\n'
        '$indent  $before$name$after\n'
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

/// Finds whether a name is read or assigned in a node, outside [skip].
class _NameUses(final String name, {required final AstNode skip})
    extends RecursiveAstVisitor<void> {
  bool read = false;
  bool assigned = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == name && !_inSkip(node)) {
      read = true;
      if (node.inSetterContext()) {
        assigned = true;
      }
    }
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    if (node.name.lexeme == name) {
      read = true;
    }
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    if (node.name.lexeme == name) {
      read = true;
    }
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (node.name.lexeme == name) {
      read = true;
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    if (node.name.lexeme == name) {
      assigned = true;
    }
    super.visitAssignedVariablePattern(node);
  }

  bool _inSkip(AstNode node) =>
      node.offset >= skip.offset && node.end <= skip.end;
}

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
