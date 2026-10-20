/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/removable.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/clause_entries.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

/// Reports the used classes and mixins whose members are all removable
/// findings and that only `with` and `implements` clauses in scanned files
/// name, like `mixin M { void m() {} }` named only in `class A with M {}`.
/// Each is reported once, and its finding also removes the type from those
/// clauses.
final class ClauseOnlyTypes {
  ClauseOnlyTypes({
    required SourceIndex sources,
    required ReferenceClassifier classifier,
    required Verdict verdict,
    required ReferenceFetch fetch,
  }) : _sources = sources,
       _classifier = classifier,
       _verdict = verdict,
       _fetch = fetch;

  final SourceIndex _sources;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;
  final ReferenceFetch _fetch;

  /// Returns a finding, with its candidate index, for each such type whose
  /// members are all in [removable], the candidate indexes of the round's
  /// removable findings. A type with a clause entry that can't be removed gets
  /// no finding. Selection ranges are fetched only for the clauses of these
  /// types. [refsByCandidate] still holds the references into [deadSpans],
  /// which name what a type is only referenced from.
  Future<List<(int, UnusedDeclaration)>> findings(
    LspClient client,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    Set<int> removable,
    DeadSpans deadSpans,
    Set<String> scannedPaths,
    String rootPath,
  ) async {
    final members = removableMembers(candidates, removable);
    final entriesOf = <int, List<ClauseEntry>>{};
    for (final (i, candidate) in candidates.indexed) {
      final outline = candidate.outline.element;
      if (statuses[i] != .used ||
          !const <OutlineKind>{.class$, .mixin}.contains(outline.kind) ||
          (candidate.symbol.children?.length ?? 0) !=
              (members[candidate.key]?.removable ?? 0)) {
        continue;
      }
      final refs = _classifier.externalRefs(candidate, liveRefs[i]);
      // The outline of every scanned file is already cached: the candidates
      // were read from it.
      final entries = [
        for (final loc in refs)
          if (scannedPaths.contains(SourceIndex.pathOf(loc.uri)))
            ?client
                .cachedOutline(.parse(loc.uri))
                ?.let(
                  (unit) =>
                      _sources.clauseEntryAt(loc, candidate.symbol.name, unit),
                ),
      ];
      if (entries.length == refs.length) {
        entriesOf[i] = entries;
      }
    }
    await _fetch.fetchSelectionRanges(
      client,
      entriesOf.values.flattened.groupFoldBy(
        (entry) => entry.path,
        (names, entry) =>
            (names ?? <Position>{})
              ..addAll(_sources.namesInClause(entry.path, entry.clause)),
      ),
    );
    // Drop a type if any of its clause entries gets no removal: the clause's
    // selection ranges aren't cached, or the entry would take every mixin of
    // a mixin application class. Dropping a type keeps its entries, which
    // changes the removals of other entries in the same clause, so repeat
    // until each type left has all its removals.
    var cuts = _sources.clauseCuts(entriesOf.values.flattened, rootPath);
    bool lacksCut(List<ClauseEntry> entries) =>
        !entries.every(cuts.containsKey);
    while (entriesOf.values.any(lacksCut)) {
      entriesOf.removeWhere((_, entries) => lacksCut(entries));
      cuts = _sources.clauseCuts(entriesOf.values.flattened, rootPath);
    }
    return [
      for (final MapEntry(key: i, value: entries) in entriesOf.entries)
        (
          i,
          _verdict.finding(
            candidates[i],
            rootPath,
            coupledRemovals: [for (final entry in entries) cuts[entry]!],
            hint: Verdict.namedOnlyInClausesHint,
            onlyReferencedFrom: deadSpans.referrersAmong(
              _classifier.externalRefs(candidates[i], refsByCandidate[i]),
            ),
          ),
        ),
    ];
  }
}
