/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/source_index.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// Recognizers for special *shapes* of reference — ones the classifier treats
/// differently from an ordinary code use.
extension ReferenceKinds on SourceIndex {
  /// Whether [loc] points at a dartdoc `[Xxx]`-style reference rather than real
  /// code — i.e. its line, in the file it points into, starts with `///`. Block
  /// (`/** */`) doc comments aren't recognized; `///` is the standard and
  /// lint-enforced style.
  bool isDocReference(Location loc) {
    final docLines = lines(SourceIndex.pathOf(loc.uri));
    final line = loc.range.start.line;
    if (line < 0 || line >= docLines.length) {
      return false;
    }
    return docLines[line].trim().startsWith('///');
  }
}
