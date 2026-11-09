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
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:ciach/src/util/reachability.dart';

final _log = Logger('ciach.finder');

/// With `transitive`, which candidates no live code reaches: every removable
/// finding starts dead, and only a reference from live code revives it (see
/// [unreached]), so dead cycles stay dead.
final class TransitiveSweep {
  TransitiveSweep({
    required ReferenceClassifier classifier,
    required Verdict verdict,
  }) : _classifier = classifier,
       _verdict = verdict;

  final ReferenceClassifier _classifier;
  final Verdict _verdict;

  /// The spans of every candidate no live code reaches, all of them assumed
  /// dead to begin with.
  DeadSpans allUnreached(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final allDead = {
      for (final (i, candidate) in candidates.indexed)
        _verdict.finding(candidate, rootPath): i,
    };
    final unreached = sweep(candidates, refsByCandidate, allDead, rootPath);
    _log.info(
      'Round 1: checking the ${plural(unreached.length, 'declaration', 'declarations')} no live code reaches…',
    );
    return unreached;
  }

  /// The removable findings no live reference reaches. [candidateOf] maps
  /// each finding to its candidate's index.
  DeadSpans sweep(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    Map<UnusedDeclaration, int> candidateOf,
    String rootPath,
  ) {
    final spans = DeadSpans.of(candidateOf.keys, rootPath);
    final removable = removableIndices(candidateOf);
    // A type's own entry in a clause counts as one of its containers, so
    // that the entry doesn't keep the type alive.
    Iterable<int> containers(String path, Position position) => [
      for (final owner in spans.ownersOf(path, position)) candidateOf[owner]!,
    ];
    final uses = [
      for (final i in removable)
        for (final loc in refsByCandidate[i])
          if (_classifier.classify(candidates[i], [loc]) == .used)
            (target: i, containers: containers(loc.path, loc.range.start)),
    ];
    final dead = unreached(removable, uses);
    return .of([
      for (final MapEntry(key: finding, value: i) in candidateOf.entries)
        if (dead.contains(i)) finding,
    ], rootPath);
  }

  /// [refsByCandidate] less the references inside [deadSpans].
  static List<List<Location>> liveRefs(
    List<List<Location>> refsByCandidate,
    DeadSpans deadSpans,
  ) => deadSpans.isEmpty
      ? refsByCandidate
      : [
          for (final refs in refsByCandidate)
            [
              for (final loc in refs)
                if (!deadSpans.covers(loc.path, loc.range.start)) loc,
            ],
        ];
}
