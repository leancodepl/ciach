/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/transitive.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// The candidates whose references came from `probeMembers`: the uses it
/// found in the files that name their type, which need not be all of them.
///
/// Such uses prove a member used, unless they all lie in dead code: a use
/// elsewhere, through a value whose type the file doesn't name, may still
/// keep it alive. Before the transitive sweep calls such a member dead, its
/// full references replace the probed ones.
final class ProbedReferences {
  ProbedReferences(this._fetch, Set<Candidate> probed) : _probed = probed;

  final ReferenceFetch _fetch;
  final Set<Candidate> _probed;

  /// [spans] after giving each probed candidate whose references all lie in
  /// them its full references in [refsByCandidate], as often as that changes
  /// them.
  Future<DeadSpans> completeIn(
    DeadSpans Function() spans,
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate, {
    required String rootPath,
  }) async {
    var dead = spans();
    while (_probed.isNotEmpty) {
      final liveRefs = TransitiveSweep.liveRefs(refsByCandidate, dead);
      final unsure = <Candidate, int>{
        for (final (i, candidate) in candidates.indexed)
          if (liveRefs[i].isEmpty && _probed.contains(candidate)) candidate: i,
      };
      if (unsure.isEmpty) {
        break;
      }
      _probed.removeAll(unsure.keys);
      final fetched = await _fetch.references(
        client,
        unsure.keys.toList(),
        totalFiles: unsure.keys.map((c) => c.path).toSet().length,
        rootPath: rootPath,
      );
      for (final (j, candidate) in fetched.checked.indexed) {
        refsByCandidate[unsure[candidate]!] = fetched.refs[j];
      }
      dead = spans();
    }
    return dead;
  }
}
