/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source_index.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// Recognizers for special *shapes* of reference — ones the classifier treats
/// differently from an ordinary code use.
extension ReferenceKinds on SourceIndex {
  /// Whether [loc] is a `[Xxx]` link in a doc comment. The link's name is its
  /// own token, so the line's first token is checked instead. `false` when
  /// the file's tokens are unknown.
  bool isDocReference(Location loc) =>
      isDocLine(SourceIndex.pathOf(loc.uri), loc.range.start.line);

  /// Whether the first token on [line] of [path] is a documentation comment.
  bool isDocLine(String path, int line) =>
      semanticTokens(path)?.firstOnLine(line)?.isDocComment ?? false;
}
