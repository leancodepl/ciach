/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/selection_range.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// The tokens and the syntax nodes of the files that a run reads.
abstract interface class FileSyntax {
  /// Returns the tokens of the file at [path], in order, or `null` when the
  /// file isn't resolved.
  List<SemanticToken>? tokensOf(String path);

  /// Returns the syntax nodes that hold [position] in the file at [path],
  /// innermost first, or `null` when the file can't be parsed or [position]
  /// isn't in it.
  SelectionRange? selectionRangeAt(String path, Position position);
}
