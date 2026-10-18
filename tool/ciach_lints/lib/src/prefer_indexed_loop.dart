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
import 'package:analyzer/dart/element/type_provider.dart';
import 'package:analyzer/dart/element/type_system.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// Flags a loop `for (var i = 0; i < xs.length; i++)` over a `List` whose
/// body reads `xs[i]`, doesn't use `xs` otherwise and doesn't change `i`.
/// `for (final x in xs)` says the same when the body uses `i` only in
/// `xs[i]`, and `for (final (i, x) in xs.indexed)` otherwise.
class PreferIndexedLoop() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_indexed_loop',
    "'for ({0})' reads the same elements without indexing the list.",
    correctionMessage: "Try replacing the loop header with 'for ({0})'.",
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
      ..addForStatement(this, visitor)
      ..addForElement(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitForStatement(ForStatement node) => _check(node);

  @override
  void visitForElement(ForElement node) => _check(node);

  void _check(ForLoop<AstNode> node) {
    if (IndexedLoopRewrite.of(node, context.typeSystem, context.typeProvider)
        case final rewrite?) {
      rule.reportAtOffset(
        node.forKeyword.offset,
        node.rightParenthesis.end - node.forKeyword.offset,
        arguments: [rewrite.header],
      );
    }
  }
}

/// Replaces the header of the flagged loop and each `xs[i]` in its body with
/// the element.
class LoopOverElements({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.loopOverElements',
    DartFixKindPriority.standard,
    "Replace with 'for ({0})'",
  );

  late final _rewrite = switch (node) {
    final ForLoop<AstNode> loop => IndexedLoopRewrite.of(
      loop,
      typeSystem,
      typeProvider,
    ),
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_rewrite?.header];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if ((node, _rewrite) case (final ForLoop<AstNode> loop, final rewrite?)) {
      await builder.addDartFileEdit(file, (builder) {
        builder.addSimpleReplacement(
          range.startEnd(loop.leftParenthesis, loop.rightParenthesis),
          '(${rewrite.header})',
        );
        for (final read in rewrite.reads) {
          final (replaced, code) = switch (_bracedInterpolation(read)) {
            final interpolation? => (interpolation, '\$${rewrite.element}'),
            null => (read, rewrite.element),
          };
          builder.addSimpleReplacement(range.node(replaced), code);
        }
      });
    }
  }
}

/// The `${xs[i]}` around [read] when `$x` can replace it, because the text
/// after it doesn't start with a letter, a digit or `_`. The fixed code then
/// has no braces that `unnecessary_brace_in_string_interps` would flag.
InterpolationExpression? _bracedInterpolation(IndexExpression read) {
  if (read.parent case final InterpolationExpression interpolation) {
    final string = interpolation.parent! as StringInterpolation;
    final next = string.elements.elementAtOrNull(
      string.elements.indexOf(interpolation) + 1,
    );
    if (next case InterpolationString(:final value)
        when !value.startsWith(RegExp(r'\w'))) {
      return interpolation;
    }
  }
  return null;
}

/// The [header] that loops over the elements of a flagged loop's list, the
/// name of the [element] in it, and the [reads] of `xs[i]` that the element
/// replaces.
class IndexedLoopRewrite._({
  required final String header,
  required final String element,
  required final List<IndexExpression> reads,
}) {
  /// The rewrite of [loop], or `null` when [loop] is no index loop over a
  /// `List` or its body needs the index loop.
  static IndexedLoopRewrite? of(
    ForLoop<AstNode> loop,
    TypeSystem typeSystem,
    TypeProvider typeProvider,
  ) {
    if (loop
        case ForLoop(
          awaitKeyword: null,
          forLoopParts: ForPartsWithDeclarations(
            variables: VariableDeclarationList(
              lateKeyword: null,
              variables: [
                VariableDeclaration(
                  initializer: IntegerLiteral(value: 0),
                  :final name,
                  declaredFragment: VariableFragment(element: final index),
                ),
              ],
            ),
            condition: BinaryExpression(
              leftOperand: SimpleIdentifier(element: final compared?),
              operator: Token(type: .LT),
              rightOperand: final bound,
            ),
            updaters: [final updater],
          ),
          :final body,
        )
        when compared == index && _incrementsOnce(updater, index)) {
      final list = _lengthTarget(bound);
      final listType = list?.staticType;
      if (list == null ||
          listType == null ||
          !_isNameChain(list) ||
          !typeSystem.isSubtypeOf(
            listType,
            typeProvider.listType(typeProvider.dynamicType),
          )) {
        return null;
      }
      final source = list.toSource();
      final uses = _BodyUses(index, source, _rootOf(list));
      body.accept(uses);
      if (uses.blocked || uses.reads.isEmpty) {
        return null;
      }
      final element = _elementName(list, loop);
      return IndexedLoopRewrite._(
        header: uses.usesIndex
            ? 'final (${name.lexeme}, $element) in $source.indexed'
            : 'final $element in $source',
        element: element,
        reads: uses.reads,
      );
    }
    return null;
  }
}

/// Whether [updater] adds one to [index]: `i++`, `++i` or `i += 1`.
bool _incrementsOnce(Expression updater, Element index) => switch (updater) {
  PostfixExpression(
    operator: Token(type: .PLUS_PLUS),
    operand: SimpleIdentifier(:final element),
  ) ||
  PrefixExpression(
    operator: Token(type: .PLUS_PLUS),
    operand: SimpleIdentifier(:final element),
  ) ||
  AssignmentExpression(
    operator: Token(type: .PLUS_EQ),
    leftHandSide: SimpleIdentifier(:final element),
    rightHandSide: IntegerLiteral(value: 1),
  ) => element == index,
  _ => false,
};

/// The `xs` of [bound] when it is `xs.length`, or `null`.
Expression? _lengthTarget(Expression bound) => switch (bound) {
  PrefixedIdentifier(
    :final prefix,
    identifier: SimpleIdentifier(name: 'length'),
  ) =>
    prefix,
  PropertyAccess(
    :final target?,
    operator: Token(type: .PERIOD),
    propertyName: SimpleIdentifier(name: 'length'),
  ) =>
    target,
  _ => null,
};

/// Whether [list] is a name or a chain of names, such as `this.items` or
/// `legend.tokenModifiers`, so that reading it once gives the same list as
/// reading it in each round of the loop.
bool _isNameChain(Expression list) => switch (list) {
  SimpleIdentifier() || PrefixedIdentifier() => true,
  PropertyAccess(:final target?, operator: Token(type: .PERIOD)) =>
    target is ThisExpression || _isNameChain(target),
  _ => false,
};

/// The element of the first name in [list], or `null` for `this`.
Element? _rootOf(Expression list) => switch (list) {
  SimpleIdentifier(:final element) => element,
  PrefixedIdentifier(:final prefix) => prefix.element,
  PropertyAccess(:final target?) => _rootOf(target),
  _ => null,
};

/// The name of the element in the new header: the singular of the list's
/// last name (`candidate` for `candidates`), or `element` when the name
/// isn't a regular plural or its singular is a reserved word (`classes`). A name that the loop already contains gets a
/// number, so that the element shadows nothing that the loop reads.
String _elementName(Expression list, ForLoop<AstNode> loop) {
  final last = switch (list) {
    SimpleIdentifier(:final name) => name,
    PrefixedIdentifier(:final identifier) => identifier.name,
    PropertyAccess(:final propertyName) => propertyName.name,
    _ => '',
  };
  final base = switch (_singularOf(last)) {
    final singular? when Keyword.keywords[singular]?.isReservedWord != true =>
      singular,
    _ => 'element',
  };
  final taken = {
    for (
      Token? token = loop.beginToken;
      token != null && token != loop.endToken.next;
      token = token.next
    )
      if (token.isIdentifier) token.lexeme,
  };
  if (!taken.contains(base)) {
    return base;
  }
  return Iterable.generate(
    taken.length + 1,
    (n) => '$base${n + 2}',
  ).firstWhere((name) => !taken.contains(name));
}

/// The singular of [plural] for the regular English plurals, or `null`:
/// `entries` → `entry`, `classes` → `class`, `xs` → `x`.
String? _singularOf(String plural) => switch (plural) {
  _ when plural.endsWith('ies') && plural.length > 3 =>
    '${plural.substring(0, plural.length - 3)}y',
  _ when RegExp(r'(ss|x|ch|sh|tus)es$').hasMatch(plural) => plural.substring(
    0,
    plural.length - 2,
  ),
  _
      when plural.endsWith('s') &&
          !plural.endsWith('ss') &&
          !plural.endsWith('us') &&
          plural.length > 1 =>
    plural.substring(0, plural.length - 1),
  _ => null,
};

/// The uses of a loop's [index] and of its list, whose source is
/// [listSource], in the loop's body: the [reads] of `xs[i]`, whether the body
/// [usesIndex] elsewhere, and whether it [blocked] the rewrite by changing
/// `i`, writing an element, or using the list or changing its [root] in
/// another way.
final class _BodyUses(
  final Element index,
  final String listSource,
  final Element? root,
) extends RecursiveAstVisitor<void> {
  final reads = <IndexExpression>[];
  bool usesIndex = false;
  bool blocked = false;

  @override
  void visitIndexExpression(IndexExpression node) {
    if (node
        case IndexExpression(
          :final target?,
          index: SimpleIdentifier(:final element),
          question: null,
          period: null,
        )
        when element == index &&
            target.toSource() == listSource &&
            !node.inSetterContext()) {
      reads.add(node);
      return;
    }
    super.visitIndexExpression(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.element == index) {
      usesIndex = true;
      blocked |= node.inSetterContext();
    } else if (node.element case final element? when element == root) {
      blocked |= node.inSetterContext();
    }
    _checkList(node);
  }

  @override
  void visitPrefixedIdentifier(PrefixedIdentifier node) {
    _checkList(node);
    super.visitPrefixedIdentifier(node);
  }

  @override
  void visitPropertyAccess(PropertyAccess node) {
    _checkList(node);
    super.visitPropertyAccess(node);
  }

  @override
  void visitAssignedVariablePattern(AssignedVariablePattern node) {
    blocked |= node.element == index || node.element == root;
    super.visitAssignedVariablePattern(node);
  }

  /// Blocks the rewrite when [node] is the list outside of an `xs[i]` read,
  /// which [visitIndexExpression] doesn't visit.
  void _checkList(Expression node) {
    blocked |= node.toSource() == listSource;
  }
}
