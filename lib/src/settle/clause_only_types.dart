/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/removable.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/clause_entries.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:collection/collection.dart';

/// Reports the used classes and mixins whose members are all removable
/// findings and that only `with` and `implements` clauses in scanned files
/// name, like `mixin M { void m() {} }` named only in `class A with M {}`.
/// Each is reported once, and its finding also removes the type from those
/// clauses.
final class ClauseOnlyTypes {
  ClauseOnlyTypes({
    required FileSyntax syntax,
    required ReferenceClassifier classifier,
    required Verdict verdict,
  }) : _syntax = syntax,
       _classifier = classifier,
       _verdict = verdict;

  final FileSyntax _syntax;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;

  /// Returns a finding, with its candidate index, for each such type whose
  /// members are all in [removable], the candidate indexes of the round's
  /// removable findings. A type with a clause entry that can't be removed gets
  /// no finding. [refsByCandidate] still holds the references into [deadSpans],
  /// which name what a type is only referenced from.
  Map<UnusedDeclaration, int> findings(
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    Set<int> removable,
    DeadSpans deadSpans,
    Set<String> scannedPaths,
    String rootPath,
  ) {
    final members = removableMembers(candidates, removable);
    final entriesOf = {
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .used &&
            const <OutlineKind>{.class$, .mixin}.contains(candidate.kind) &&
            candidate.outline.children.length ==
                (members[candidate.key]?.removable ?? 0))
          i: ?_clauseEntriesNaming(candidate, liveRefs[i], scannedPaths),
    };
    // Drop a type if any of its clause entries gets no removal, because the
    // entry would take every mixin of a mixin application class. Dropping a
    // type keeps its entries, which changes the removals of other entries in
    // the same clause, so repeat until each type left has all its removals.
    var cuts = clauseCuts(entriesOf.values.flattened, rootPath);
    bool lacksCut(List<ClauseEntry> entries) =>
        !entries.every(cuts.containsKey);
    while (entriesOf.values.any(lacksCut)) {
      entriesOf.removeWhere((_, entries) => lacksCut(entries));
      cuts = clauseCuts(entriesOf.values.flattened, rootPath);
    }
    return {
      for (final MapEntry(key: i, value: entries) in entriesOf.entries)
        _verdict.finding(
          candidates[i],
          rootPath,
          coupledRemovals: [for (final entry in entries) cuts[entry]!],
          hint: Verdict.namedOnlyInClausesHint,
          onlyReferencedFrom: deadSpans.referrersAmong(
            _classifier.externalRefs(candidates[i], refsByCandidate[i]),
          ),
        ): i,
    };
  }

  /// Returns the clause entries that the [refs] to [type] from outside it are
  /// in, or `null` when one of those references is not in a clause entry in a
  /// scanned file.
  List<ClauseEntry>? _clauseEntriesNaming(
    Candidate type,
    List<Location> refs,
    Set<String> scannedPaths,
  ) {
    final external = _classifier.externalRefs(type, refs);
    final entries = [
      for (final loc in external)
        if (scannedPaths.contains(loc.path))
          ?_syntax.clauseEntryAt(loc, type.outline.element),
    ];
    return entries.length == external.length ? entries : null;
  }
}
