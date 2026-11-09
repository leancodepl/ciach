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
///
/// This is the semantic heart of the tool: everything that discounts a
/// reference (a declaration's own span, the `State<Self>` pairing, doc-comment
/// links, type-pattern matches) lives here, kept apart from the run
/// orchestration.
class ReferenceClassifier {
  ReferenceClassifier(this._syntax, {required this.unusedUnionMembers});

  final FileSyntax _syntax;

  /// Whether a class matched only by a type pattern (never constructed) counts
  /// as dead — the opt-in `--also union-members` behavior.
  final bool unusedUnionMembers;

  /// Classifies [candidate] from its [refs].
  ///
  /// A reference inside the candidate's own span never counts (see
  /// [isSelfReference]). Of the rest: any real (non-doc) one means used, only
  /// doc-comment links means doc-only, none means unused.
  RefStatus classify(Candidate candidate, List<Location> refs) {
    // An extension type is a type, so self-references don't keep it alive.
    if (candidate.isClassOrMixin || candidate.isExtensionType) {
      return _classifyClass(candidate, refs);
    }
    final external = externalRefs(candidate, refs);
    if (external.isEmpty) {
      return .unused;
    }
    return external.every(_syntax.isDocReference) ? .docOnly : .used;
  }

  /// [refs] less the ones inside [candidate]'s own span.
  List<Location> externalRefs(Candidate candidate, List<Location> refs) =>
      refs.whereNot((loc) => isSelfReference(candidate, loc)).toList();

  /// Classifies a class by its references, ignoring self-references.
  ///
  /// A class is used only if some reference is a real (non-doc) reference from
  /// *outside* the class itself; if the only outside references are doc-comment
  /// links it is doc-only, and otherwise (only self-references, or none at all)
  /// it is unused. This is deliberately conservative: any single unexplained
  /// outside reference keeps the class alive, so the failure mode is missing a
  /// dead class, never deleting a live one.
  RefStatus _classifyClass(Candidate candidate, List<Location> refs) {
    final external = externalRefs(candidate, refs);
    final code = external.whereNot(_syntax.isDocReference).toList();
    if (code.isEmpty) {
      return external.isEmpty ? .unused : .docOnly;
    }
    // With --also union-members, a reference that is confidently a *type
    // pattern* (a `case`/if-case/while-case pattern, or a switch-expression
    // arm) is a *match*, not a construction: if the type is never
    // constructed, no such match can ever fire, so it is discounted like a
    // self-reference. Any reference that is not confidently a type pattern
    // keeps the class alive — the conservative choice (nested sub-patterns
    // and pattern-variable declarations are intentionally not recognized).
    // Matched-only-by-a-pattern (never constructed) is dead code, not a softer
    // doc-only report.
    return unusedUnionMembers && code.every(_syntax.isTypePattern)
        ? .unused
        : .used;
  }

  /// Whether [loc] is a reference to [candidate] that does not count as a use:
  /// one inside the declaration's own span (body, signature, doc and
  /// annotation lines — text that goes when it does, so a recursive call or
  /// the unnamed constructor's declaration keeps nothing alive), or the
  /// `State<Foo>` pairing ([FileSyntax.isStateTypeArgument]).
  bool isSelfReference(Candidate candidate, Location loc) =>
      (loc.path == candidate.path &&
          candidate.outline.range.contains(loc.range.start)) ||
      _syntax.isStateTypeArgument(loc);

  /// Whether [candidate] — already classified as unused under
  /// `--also union-members` — is kept dead by *type patterns*: at least one
  /// of its non-self, non-doc references is a `case`/switch-expression pattern
  /// match rather than a construction.
  bool isPatternMatchedClass(Candidate candidate, List<Location> refs) =>
      refs.any(
        (loc) =>
            !isSelfReference(candidate, loc) &&
            !_syntax.isDocReference(loc) &&
            _syntax.isTypePattern(loc),
      );
}
