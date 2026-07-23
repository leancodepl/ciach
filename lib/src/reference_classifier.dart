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
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// Decides whether a declaration is used, unused, or referenced only from doc
/// comments, from the references the analysis server reported for it.
///
/// This is the semantic heart of the tool: everything that discounts a
/// reference (self-references, the `State<Self>` pairing, doc-comment links,
/// type-pattern matches) lives here, kept apart from the run orchestration.
class ReferenceClassifier {
  ReferenceClassifier(this._sources, {required this.unusedUnionMembers});

  final SourceIndex _sources;

  /// Whether a class matched only by a type pattern (never constructed) counts
  /// as dead — the opt-in `--unused-union-members` behaviour.
  final bool unusedUnionMembers;

  /// Classifies [candidate] from the [refs] reported for it.
  ///
  /// Non-class candidates keep the simple rule: any real (non-doc) reference
  /// means used, only doc-comment links means doc-only, none means unused.
  ///
  /// Classes get [_classifyClass], which discounts *self-references* — the
  /// class's own body, and the `State<Self>` StatefulWidget pairing — so a
  /// class kept alive only by its own unnamed constructor's declaration (whose
  /// name coincides with the class) is correctly seen as dead.
  RefStatus classify(Candidate candidate, List<Location> refs) {
    if (candidate.symbol.kind == .class$) {
      return _classifyClass(candidate, refs);
    }
    if (refs.isEmpty) {
      return .unused;
    }
    return refs.any((loc) => !_sources.isDocReference(loc)) ? .used : .docOnly;
  }

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
      if (isSelfClassReference(candidate, loc)) {
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

  /// Whether [loc] is a reference to [candidate] that does not count as a use.
  ///
  /// Two shapes qualify:
  ///
  /// 1. A reference inside the class's own source span — its body, signature,
  ///    or leading doc/annotation lines. This covers the unnamed constructor's
  ///    declaration, a `State<Foo>` return type on the widget's own
  ///    `createState`, and any purely-internal self-use.
  /// 2. A `State<Foo>` type-argument reference anywhere — the StatefulWidget
  ///    pairing (see [FlutterWidgets.isStatePairingReference]).
  bool isSelfClassReference(Candidate candidate, Location loc) {
    if (SourceIndex.pathOf(loc.uri) == candidate.path) {
      final top = candidate.symbol.metadataTopLine(
        _sources.lines(candidate.path),
      );
      final pos = loc.range.start;
      if (pos.line >= top && pos.atOrBefore(candidate.symbol.range.end)) {
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
            !isSelfClassReference(candidate, loc) &&
            !_sources.isDocReference(loc) &&
            _sources.isPatternRef(loc),
      );
}
