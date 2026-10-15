/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/member_probe.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/transitive.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// The candidates whose references came from a [MemberProbe]: the uses it
/// found in the files that name their type, which need not be all of them.
///
/// Such uses prove a member used, unless they all lie in dead code: a use
/// elsewhere, through a value whose type the file doesn't name, may still
/// keep it alive. Before the transitive sweep calls such a member dead, the
/// probe looks for a use outside dead code among the member's other mentions,
/// and only if it finds none do its full references replace the probed ones.
final class ProbedReferences {
  ProbedReferences(this._fetch, this._probe) : _probed = {...?_probe?.used};

  final ReferenceFetch _fetch;
  final MemberProbe? _probe;
  final Set<Candidate> _probed;

  /// [spans] after giving each probed candidate whose references all lie in
  /// them a use outside them, or else its full references, in
  /// [refsByCandidate], as often as that changes them.
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
      await _complete(client, unsure, refsByCandidate, dead, rootPath);
      dead = spans();
    }
    return dead;
  }

  /// Gives each of the [unsure] candidates, with its index in
  /// [refsByCandidate], a use the probe finds outside [dead], or else all its
  /// references.
  Future<void> _complete(
    LspClient client,
    Map<Candidate, int> unsure,
    List<List<Location>> refsByCandidate,
    DeadSpans dead,
    String rootPath,
  ) async {
    final live = await Future.wait([
      for (final candidate in unsure.keys)
        _probe!.liveUse(candidate, dead.covers),
    ]);
    final unfound = <Candidate>[];
    for (final (j, MapEntry(key: candidate, value: i))
        in unsure.entries.indexed) {
      if (live[j] case final use?) {
        refsByCandidate[i] = [...refsByCandidate[i], use];
      } else {
        unfound.add(candidate);
      }
    }
    if (unfound.isEmpty) {
      return;
    }
    _probed.removeAll(unfound);
    final fetched = await _fetch.references(
      client,
      unfound,
      totalFiles: unfound.map((c) => c.path).toSet().length,
      rootPath: rootPath,
    );
    for (final (j, candidate) in fetched.checked.indexed) {
      refsByCandidate[unsure[candidate]!] = fetched.refs[j];
    }
  }
}
