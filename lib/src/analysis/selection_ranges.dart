/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:ciach/src/analysis/argument_names.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/selection_range.dart';

/// Returns the syntax nodes of [unit] that hold [offset], innermost first,
/// as `DartSelectionRangeComputer` in the analysis server lists them: each
/// node whose range differs from the range of the node inside it, without the
/// name and type parameters of a class header. Where no node holds [offset],
/// the range is empty at [offset].
SelectionRange selectionRangeIn(CompilationUnit unit, int offset) {
  final ranges = <({int start, int end})>[];
  void add(int start, int end) {
    if (ranges.lastOrNull != (start: start, end: end)) {
      ranges.add((start: start, end: end));
    }
  }

  for (
    var node = unit.nodeCovering(offset: offset);
    node != null && node != unit;
    node = node.parent
  ) {
    if (node is NameWithTypeParameters) {
      continue;
    }
    for (final (:start, :end) in _innerRanges(node, offset)) {
      add(start, end);
    }
    add(node.offset, node.end);
  }
  if (ranges.isEmpty) {
    return .new(range: unit.lineInfo.rangeOf(offset, offset));
  }
  SelectionRange? outer;
  for (final (:start, :end) in ranges.reversed) {
    outer = .new(range: unit.lineInfo.rangeOf(start, end), parent: outer);
  }
  return outer!;
}

/// The ranges inside [node] that the server lists before [node] for
/// [offset], innermost first: for a parameter, the parameter without its
/// default value when [offset] is before it, and for a named argument or a
/// named record field, its name and its name with the colon when [offset] is
/// in them.
///
/// From analyzer 13.0.0 on, these are tokens of [node], so the server adds
/// their ranges itself. Before, a parameter with a default value, such as
/// `int x = 1`, wraps the parameter `int x`, and the name of a named argument
/// is a label, so their nodes have these ranges already.
Iterable<({int start, int end})> _innerRanges(AstNode node, int offset) sync* {
  switch (node) {
    case FormalParameter():
      final children = node.childEntities.toList();
      final defaultAt = children.indexWhere(
        (child) => const {
          TokenType.EQ,
          TokenType.COLON,
        }.contains(_firstTokenOf(child).type),
      );
      if (defaultAt > 0 && offset < children[defaultAt].offset) {
        yield (start: node.offset, end: children[defaultAt - 1].end);
      }
    case AstNode(parent: ArgumentList() || RecordLiteral()):
      if (argumentNameOf(node) case (
        :final name,
        :final colon,
      ) when offset <= colon.end) {
        yield (start: name.offset, end: name.end);
        yield (start: name.offset, end: colon.end);
      }
  }
}

/// [entity] when it is a token, or its first token.
Token _firstTokenOf(SyntacticEntity entity) => switch (entity) {
  final Token token => token,
  final AstNode node => node.beginToken,
  _ => throw ArgumentError.value(entity, 'entity'),
};
