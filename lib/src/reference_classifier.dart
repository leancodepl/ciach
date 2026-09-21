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
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// Decides whether a declaration is used, unused, or referenced only from doc
/// comments, from the references the analysis server reported for it.
///
/// This is the semantic heart of the tool: everything that discounts a
/// reference (a declaration's own span, the `State<Self>` pairing, doc-comment
/// links, type-pattern matches) lives here, kept apart from the run
/// orchestration.
class ReferenceClassifier {
  ReferenceClassifier(this._sources, {required this.unusedUnionMembers});

  final SourceIndex _sources;

  /// Whether a class matched only by a type pattern (never constructed) counts
  /// as dead — the opt-in `--unused-union-members` behavior.
  final bool unusedUnionMembers;

  /// Classifies [candidate] from the [refs] reported for it, consulting
  /// [crossLib] as a secondary check on members that appear unreferenced.
  ///
  /// A reference inside the candidate's own span never counts (see
  /// [isSelfReference]). Of the rest: any real (non-doc) one means used, only
  /// doc-comment links means doc-only, none means unused.
  RefStatus classify(
    Candidate candidate,
    List<Location> refs,
    CrossLibraryReferences crossLib,
  ) {
    // An extension type is a type, so self-references don't keep it alive.
    if (candidate.symbol.kind == .class$ || candidate.isExtensionType) {
      return _classifyClass(candidate, refs);
    }
    final external = externalRefs(candidate, refs);
    if (external.isEmpty) {
      return crossLib.isRecovered(candidate) ? .used : .unused;
    }
    return external.every(_sources.isDocReference) ? .docOnly : .used;
  }

  /// [refs] less the ones inside [candidate]'s own span.
  List<Location> externalRefs(Candidate candidate, List<Location> refs) => [
    for (final loc in refs)
      if (!isSelfReference(candidate, loc)) loc,
  ];

  /// Classifies a class by its references, ignoring self-references.
  ///
  /// A class is used only if some reference is a real (non-doc) reference from
  /// *outside* the class itself; if the only outside references are doc-comment
  /// links it is doc-only, and otherwise (only self-references, or none at all)
  /// it is unused. This is deliberately conservative: any single unexplained
  /// outside reference keeps the class alive, so the failure mode is missing a
  /// dead class, never deleting a live one.
  RefStatus _classifyClass(Candidate candidate, List<Location> refs) {
    var hasExternalDoc = false;
    var hasPatternMatch = false;
    for (final loc in refs) {
      if (isSelfReference(candidate, loc)) {
        continue;
      }
      if (_sources.isDocReference(loc)) {
        hasExternalDoc = true;
        continue;
      }
      // With --unused-union-members, a reference that is confidently a *type
      // pattern* (a `case`/if-case/while-case pattern, or a switch-expression
      // arm) is a *match*, not a construction: if the type is never
      // constructed, no such match can ever fire, so it is discounted like a
      // self-reference. Any reference that is not confidently a type pattern
      // keeps the class alive — the conservative choice (nested sub-patterns
      // and pattern-variable declarations are intentionally not recognized).
      if (unusedUnionMembers && _sources.isPatternRef(loc)) {
        hasPatternMatch = true;
        continue;
      }
      // A real, non-pattern reference from outside: the class is used.
      return .used;
    }
    // Matched-only-by-a-pattern (never constructed) is dead code, not a softer
    // doc-only report.
    if (hasPatternMatch) {
      return .unused;
    }
    return hasExternalDoc ? .docOnly : .unused;
  }

  /// Whether [loc] is a reference to [candidate] that does not count as a use:
  /// one inside the declaration's own span (body, signature, doc and
  /// annotation lines — text that goes when it does, so a recursive call or
  /// the unnamed constructor's declaration keeps nothing alive), or the
  /// `State<Foo>` pairing ([FlutterWidgets.isStatePairingReference]).
  bool isSelfReference(Candidate candidate, Location loc) {
    if (SourceIndex.pathOf(loc.uri) == candidate.path) {
      final range = candidate.outline.range;
      final pos = loc.range.start;
      if (range.start.atOrBefore(pos) && pos.atOrBefore(range.end)) {
        return true;
      }
    }
    return _sources.isStatePairingReference(candidate.symbol.name, loc);
  }

  /// Whether [candidate] — already classified as unused under
  /// `--unused-union-members` — is kept dead by *type patterns*: at least one
  /// of its non-self, non-doc references is a `case`/switch-expression pattern
  /// match rather than a construction.
  bool isPatternMatchedClass(Candidate candidate, List<Location> refs) =>
      refs.any(
        (loc) =>
            !isSelfReference(candidate, loc) &&
            !_sources.isDocReference(loc) &&
            _sources.isPatternRef(loc),
      );
}
