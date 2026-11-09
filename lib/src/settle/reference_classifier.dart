/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:collection/collection.dart';

/// Decides whether a declaration is used, unused, or referenced only from doc
/// comments, from its references.
class ReferenceClassifier {
  ReferenceClassifier(this._syntax, {required this.unusedUnionMembers});

  final FileSyntax _syntax;

  /// Whether a class matched only by a type pattern (never constructed) counts
  /// as dead — the opt-in `--also union-members` behavior.
  final bool unusedUnionMembers;

  /// Classifies [candidate] from its [refs]. A reference inside its own span
  /// never counts (see [isSelfReference]). Of the rest, any code reference
  /// means used, and doc-comment links alone mean doc-only.
  ///
  /// With [unusedUnionMembers], a class or extension type that only type
  /// patterns name is unused: a match can't fire on a type that nothing
  /// constructs. Any other reference keeps it, so a missed pattern keeps a
  /// dead type rather than deleting a live one.
  RefStatus classify(Candidate candidate, List<Location> refs) {
    final external = externalRefs(candidate, refs);
    final code = external.whereNot(_syntax.isDocReference).toList();
    if (code.isEmpty) {
      return external.isEmpty ? .unused : .docOnly;
    }
    return unusedUnionMembers &&
            (candidate.isClassOrMixin || candidate.isExtensionType) &&
            code.every(_syntax.isTypePattern)
        ? .unused
        : .used;
  }

  /// [refs] less the ones inside [candidate]'s own span.
  List<Location> externalRefs(Candidate candidate, List<Location> refs) =>
      refs.whereNot((loc) => isSelfReference(candidate, loc)).toList();

  /// Whether [loc] is a reference to [candidate] that does not count as a use:
  /// one inside the declaration's own span (body, signature, doc and
  /// annotation lines — text that goes when it does, so a recursive call or
  /// the unnamed constructor's declaration keeps nothing alive), or the
  /// `State<Foo>` pairing ([FileSyntax.isStateTypeArgument]).
  bool isSelfReference(Candidate candidate, Location loc) =>
      (loc.path == candidate.path &&
          candidate.outline.range.contains(loc.range.start)) ||
      _syntax.isStateTypeArgument(loc);

  /// Whether [candidate], unused under `--also union-members`, is kept dead
  /// by type patterns: one of its code references is a pattern.
  bool isPatternMatchedClass(Candidate candidate, List<Location> refs) =>
      externalRefs(
        candidate,
        refs,
      ).whereNot(_syntax.isDocReference).any(_syntax.isTypePattern);
}
