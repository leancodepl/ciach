/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/selection_range.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// The tokens and syntax nodes that a test sets, by file path.
final class FakeSyntax implements FileSyntax {
  final tokens = <String, List<SemanticToken>>{};

  /// The syntax nodes at each position, innermost first.
  final nodes = <String, Map<Position, SelectionRange>>{};

  @override
  List<SemanticToken>? tokensOf(String path) => tokens[path];

  @override
  SelectionRange? selectionRangeAt(String path, Position position) =>
      nodes[path]?[position];
}
