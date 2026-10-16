/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/transitive.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// The candidates whose references came from `probeMembers`: the uses it
/// found in the files that name their type, which need not be all of them.
///
/// Such uses prove a member used, unless they all lie in dead code: a use
/// elsewhere, through a value whose type the file doesn't name, may still
/// keep it alive. Before the transitive sweep calls such a member dead, the
/// server's full references of the member are added to the probed uses, and
/// to the references of its namesakes in other conditional-import variants,
/// which share them.
final class ProbedReferences {
  ProbedReferences({
    required ReferenceFetch fetch,
    required ReferenceClassifier classifier,
    required ConditionalImports conditionalImports,
    required LspClient client,
    required List<Candidate> candidates,
    required String rootPath,
    required Set<Candidate> probed,
  }) : _fetch = fetch,
       _classifier = classifier,
       _conditionalImports = conditionalImports,
       _client = client,
       _candidates = candidates,
       _rootPath = rootPath,
       _probed = {...probed};

  final ReferenceFetch _fetch;
  final ReferenceClassifier _classifier;
  final ConditionalImports _conditionalImports;
  final LspClient _client;
  final List<Candidate> _candidates;
  final String _rootPath;

  /// The probed candidates whose full references haven't been fetched yet.
  final Set<Candidate> _probed;

  late final _namesakes = _conditionalImports.namesakesIn(_candidates);

  /// Returns [refsByCandidate] with its full references added to each
  /// probed candidate that the dead [spans] leave without a live use, and to
  /// its namesakes, or [refsByCandidate] itself when there is none.
  ///
  /// Such a candidate's probed uses all lie in dead code, but the files that
  /// the probe read may not hold all its uses: `make().close()` calls
  /// `Helper.close` in a file that never names `Helper`. So ciach asks the
  /// server for every reference before it calls the candidate dead. The added
  /// references can only shrink the spans, so a candidate is asked for at
  /// most once.
  Future<List<List<Location>>> withFullReferences(
    List<List<Location>> refsByCandidate,
    DeadSpans spans,
  ) async {
    final liveRefs = TransitiveSweep.liveRefs(refsByCandidate, spans);
    final unsure = <Candidate, int>{
      for (final (i, candidate) in _candidates.indexed)
        if (liveRefs[i].isEmpty && _probed.contains(candidate)) candidate: i,
    };
    if (unsure.isEmpty) {
      return refsByCandidate;
    }
    _probed.removeAll(unsure.keys);
    final fetched = await _fetch.references(
      _client,
      unsure.keys.toList(),
      totalFiles: unsure.keys.map((c) => c.path).toSet().length,
      rootPath: _rootPath,
    );
    final added =
        [
          for (final (j, candidate) in fetched.checked.indexed) ...[
            (index: unsure[candidate]!, refs: fetched.refs[j]),
            // A namesake in another variant shares the references, as
            // `ConditionalImports.share` does with the first ones.
            for (final namesake in _namesakes[unsure[candidate]!])
              (
                index: namesake,
                refs: _classifier.externalRefs(candidate, fetched.refs[j]),
              ),
          ],
        ].groupFoldBy<int, Set<Location>>(
          (addition) => addition.index,
          (refs, addition) => (refs ?? {})..addAll(addition.refs),
        );
    return [
      for (final (i, refs) in refsByCandidate.indexed)
        if (added[i] case final extra?) {...refs, ...extra}.toList() else refs,
    ];
  }
}
