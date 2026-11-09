/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/selection_range.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';

/// Structural checks over a declaration or a reference, read from the tokens
/// and the syntax nodes in [SourceIndex]. When a check cannot confirm a
/// shape, it answers in the direction that keeps code.
extension StructuralChecks on SourceIndex {
  /// Whether reference [loc] is an enum name followed by `.values`: the name
  /// and the `values` token form one expression node.
  /// `OutlineElement.usesOwnValues` covers the reads in the enum's body.
  bool isDotValuesRef(Location loc) {
    final path = loc.path;
    final position = loc.range.start;
    final tokens = semanticTokens(path);
    final parent = selectionRangeAt(path, position)?.parent;
    if (tokens == null || parent == null || parent.range.start != position) {
      return false;
    }
    final last = tokens.lastIn(parent.range);
    return last != null &&
        last.type == 'property' &&
        last.text == 'values' &&
        last.start != position;
  }

  /// Whether reference [loc] to a class is a type pattern rather than a use.
  /// The nodes around it are the type, the pattern it heads (`Circle()`,
  /// `Circle c`) and the pattern's parent. It is a pattern when the parent
  /// starts with `case`, or is a switch-expression arm whose own parent starts
  /// with `switch`. Anything else, or a reference with no nodes, is a use.
  bool isPatternRef(Location loc) {
    final path = loc.path;
    final position = loc.range.start;
    final tokens = semanticTokens(path);
    final type = selectionRangeAt(path, position);
    final pattern = type?.parent;
    final clause = pattern?.parent;
    if (tokens == null || type == null || pattern == null || clause == null) {
      return false;
    }
    if (type.range.start != position || pattern.range.start != position) {
      return false;
    }
    bool opensWith(SelectionRange node, String keyword) {
      final first = tokens.startingAt(node.range.start);
      return first != null && first.isKeyword && first.text == keyword;
    }

    if (opensWith(clause, 'case')) {
      return true;
    }
    final switchNode = clause.parent;
    return clause.range.start == position &&
        switchNode != null &&
        opensWith(switchNode, 'switch');
  }
}
