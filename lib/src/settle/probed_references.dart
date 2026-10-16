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
    required List<List<Location>> refsByCandidate,
    required String rootPath,
    required Set<Candidate> probed,
  }) : _fetch = fetch,
       _classifier = classifier,
       _conditionalImports = conditionalImports,
       _client = client,
       _candidates = candidates,
       _refsByCandidate = refsByCandidate,
       _rootPath = rootPath,
       _probed = {...probed};

  final ReferenceFetch _fetch;
  final ReferenceClassifier _classifier;
  final ConditionalImports _conditionalImports;
  final LspClient _client;
  final List<Candidate> _candidates;
  final List<List<Location>> _refsByCandidate;
  final String _rootPath;
  final Set<Candidate> _probed;

  late final _namesakes = _conditionalImports.namesakesIn(_candidates);

  /// Returns the dead spans that [spans] computes from the current
  /// references, after giving each probed candidate that has no live use
  /// left its full references.
  ///
  /// Such a candidate's probed uses all lie in dead code, but the files that
  /// the probe read may not hold all its uses: `make().close()` calls
  /// `Helper.close` in a file that never names `Helper`. So ciach asks the
  /// server for every reference before it calls the candidate dead, and
  /// recomputes the spans, which the added references can only shrink. A
  /// candidate is asked for at most once.
  Future<DeadSpans> addFullReferences(DeadSpans Function() spans) async {
    final dead = spans();
    final liveRefs = TransitiveSweep.liveRefs(_refsByCandidate, dead);
    final unsure = <Candidate, int>{
      for (final (i, candidate) in _candidates.indexed)
        if (liveRefs[i].isEmpty && _probed.contains(candidate)) candidate: i,
    };
    if (unsure.isEmpty) {
      return dead;
    }
    _probed.removeAll(unsure.keys);
    final fetched = await _fetch.references(
      _client,
      unsure.keys.toList(),
      totalFiles: unsure.keys.map((c) => c.path).toSet().length,
      rootPath: _rootPath,
    );
    for (final (j, candidate) in fetched.checked.indexed) {
      final i = unsure[candidate]!;
      _add(i, fetched.refs[j]);
      // A namesake in another variant shares the references, as
      // `ConditionalImports.share` does with the first ones.
      for (final namesake in _namesakes[i]) {
        _add(namesake, _classifier.externalRefs(candidate, fetched.refs[j]));
      }
    }
    return spans();
  }

  void _add(int i, List<Location> refs) =>
      _refsByCandidate[i] = {..._refsByCandidate[i], ...refs}.toList();
}
