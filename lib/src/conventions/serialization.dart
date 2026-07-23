/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';

/// A JSON-value return type on a `toJson`'s declaration line, before the name.
final _toJsonJsonReturn = RegExp(
  r'\b(?:Map|List|String|int|double|num|bool|Object|dynamic)\b\s*(?:<[^;{]*>)?\s*\??\s*$',
);

/// `json_serializable`/hand-rolled JSON serialization conventions.
extension SerializationHooks on SourceIndex {
  /// Whether [candidate] is a `toJson()` serialization hook — a
  /// zero-required-arg method named `toJson` returning any JSON value
  /// (`Map`/`List`/`String`/`num`/`int`/`double`/`bool`, or `Object`/`dynamic`).
  /// `jsonEncode(obj)` dispatches to it dynamically with no source-level
  /// `.toJson()` token, so the reference search can't see that use; exempt it
  /// for any class, annotated or not.
  bool isToJsonHook(Candidate candidate) {
    final symbol = candidate.symbol;
    if (symbol.kind != .method ||
        symbol.name != 'toJson' ||
        !symbol.hasNoParameters) {
      return false;
    }
    final fileLines = lines(candidate.path);
    final line = symbol.selectionRange.start.line;
    if (line < 0 || line >= fileLines.length) {
      return false;
    }
    final col = symbol.selectionRange.start.character;
    final text = fileLines[line];
    final beforeName = col <= text.length ? text.substring(0, col) : text;
    return _toJsonJsonReturn.hasMatch(beforeName);
  }
}
