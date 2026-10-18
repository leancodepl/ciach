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
import 'package:collection/collection.dart';

/// Flags a loop `for (var i = 0; i < xs.length; i++)` over a `List` whose
/// body reads `xs[i]`, doesn't use `xs` otherwise and doesn't change `i`.
/// `for (final x in xs)` says the same when the body uses `i` only in
/// `xs[i]`, and `for (final (i, x) in xs.indexed)` otherwise.
class PreferForInLoop() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_for_in_loop',
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
    if (ForInLoopRewrite.of(node, context.typeSystem, context.typeProvider)
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
/// the element, and removes a `final x = xs[i];` whose name the element takes.
/// A new name is one linked edit, so that an editor lets the user rename every
/// copy at once.
class LoopOverElements({required super.context})
    extends ResolvedCorrectionProducer {
  static const _elementGroup = 'element';

  static const kind = FixKind(
    'ciach_lints.fix.loopOverElements',
    DartFixKindPriority.standard,
    "Replace with 'for ({0})'",
  );

  late final _rewrite = switch (node) {
    final ForLoop<AstNode> loop => ForInLoopRewrite.of(
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
        void writeElement(EditBuilder builder) {
          if (rewrite.declaration == null) {
            builder.addSimpleLinkedEdit(_elementGroup, rewrite.element);
          } else {
            builder.write(rewrite.element);
          }
        }

        builder.addReplacement(
          range.startEnd(loop.leftParenthesis, loop.rightParenthesis),
          (builder) {
            builder.write('(${rewrite.beforeElement}');
            writeElement(builder);
            builder.write('${rewrite.afterElement})');
          },
        );
        if (rewrite.declaration case final declaration?) {
          builder.addDeletion(
            range.endEnd(declaration.beginToken.previous!, declaration),
          );
        }
        for (final read in rewrite.reads) {
          final interpolation = _bracedInterpolation(read);
          builder.addReplacement(range.node(interpolation ?? read), (builder) {
            if (interpolation != null) {
              builder.write(r'$');
            }
            writeElement(builder);
          });
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

/// The new header of a flagged loop, which declares the [element] between
/// [beforeElement] and [afterElement], the `final x = xs[i];` [declaration]
/// that the element replaces, if any, and the other [reads] of `xs[i]`.
class ForInLoopRewrite._({
  required final String beforeElement,
  required final String element,
  required final String afterElement,
  required final VariableDeclarationStatement? declaration,
  required final List<IndexExpression> reads,
}) {
  /// The new header, such as `final (i, x) in xs.indexed`.
  String get header => '$beforeElement$element$afterElement';

  /// The rewrite of [loop], or `null` when [loop] is no index loop over a
  /// `List` or its body needs the index loop.
  static ForInLoopRewrite? of(
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
      final declaration = _declarationOfRead(body, uses.reads);
      final declared = declaration?.variables.variables.single;
      return ForInLoopRewrite._(
        beforeElement: uses.usesIndex ? 'final (${name.lexeme}, ' : 'final ',
        element: declared?.name.lexeme ?? _unusedName(loop),
        afterElement: uses.usesIndex ? ') in $source.indexed' : ' in $source',
        declaration: declaration,
        reads: uses.reads
            .whereNot((read) => read == declared?.initializer)
            .toList(),
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

/// The first statement in the block of a loop with the [body] that is
/// `final x = xs[i];`, one of [reads] with no type, or `null`. The element can
/// take its name.
VariableDeclarationStatement? _declarationOfRead(
  AstNode body,
  List<IndexExpression> reads,
) => switch (body) {
  Block(:final statements) =>
    statements.whereType<VariableDeclarationStatement>().firstWhereOrNull(
      (statement) => switch (statement.variables) {
        VariableDeclarationList(
          isFinal: true,
          lateKeyword: null,
          type: null,
          variables: [VariableDeclaration(:final IndexExpression initializer)],
        ) =>
          reads.contains(initializer),
        _ => false,
      },
    ),
  _ => null,
};

/// `element`, with a number when [loop] already contains that name, so that
/// the element shadows nothing that the loop reads.
String _unusedName(ForLoop<AstNode> loop) {
  final taken = {
    for (
      Token? token = loop.beginToken;
      token != null && token != loop.endToken.next;
      token = token.next
    )
      if (token.isIdentifier) token.lexeme,
  };
  return Iterable.generate(
    taken.length + 1,
    (n) => n == 0 ? 'element' : 'element${n + 1}',
  ).firstWhere((name) => !taken.contains(name));
}

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
