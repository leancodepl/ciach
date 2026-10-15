/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:collection/collection.dart';

/// How many types extend, implement or mix in each type, by name, as the
/// headers of the scanned files read.
///
/// A references search for a member builds the member's override hierarchy
/// every time, which for a type with hundreds of subtypes takes seconds. This
/// count only decides which members are looked up a cheaper way first, so it
/// may guess: a type argument or bound in a header counts too, and namesakes
/// from different libraries add up.
final class SubtypeCounts {
  /// The names of the types whose headers name each type.
  final _direct = <String, Set<String>>{};

  final _counts = <String, int>{};

  /// Records the headers of the types declared in [unit], from the file's
  /// [tokens].
  void add(Outline unit, List<SemanticToken> tokens) {
    for (final type in unit.children) {
      final OutlineElement(:kind, :name, :range) = type.element;
      if (range == null || !_typeKinds.contains(kind)) {
        continue;
      }
      final bodyStart =
          type.children.firstOrNull?.range.start ?? type.codeRange.end;
      var inClause = false;
      for (final token in tokens.between(range.end, bodyStart)) {
        if (token.isKeyword) {
          inClause = inClause || _clauseKeywords.contains(token.text);
        } else if (inClause && token.type == 'class') {
          (_direct[token.text] ??= {}).add(name);
        }
      }
    }
    _counts.clear();
  }

  /// How many types have [name] among their supertypes, directly or not.
  int of(String name) => _counts[name] ??= _subtypes(name, {}).length;

  Set<String> _subtypes(String name, Set<String> seen) {
    final subtypes = <String>{};
    for (final subtype in _direct[name] ?? const <String>{}) {
      if (seen.add(subtype)) {
        subtypes
          ..add(subtype)
          ..addAll(_subtypes(subtype, seen));
      }
    }
    return subtypes;
  }

  static const _typeKinds = <OutlineKind>{
    .class$,
    .classTypeAlias,
    .mixin,
    .enum$,
    .extensionType,
  };

  static const _clauseKeywords = {'extends', 'with', 'implements', 'on'};
}
