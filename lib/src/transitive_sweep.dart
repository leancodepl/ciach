import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/verdict.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

final _log = Logger('ciach.finder');

/// The `--transitive` sweep: which removable findings no live code reaches.
///
/// Every candidate starts dead and only what live code reaches is revived
/// (see [unreached]), so dead cycles are reported too. The settler then
/// settles the verdicts in rounds, and what a round keeps revives what it
/// reaches, until the dead set stops changing.
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
  DeadSpans unreachedCandidates(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final allDead = {
      for (var i = 0; i < candidates.length; i++)
        _verdict.finding(candidates[i], rootPath): i,
    };
    final unreached = sweep(
      candidates,
      refsByCandidate,
      .empty,
      allDead,
      rootPath,
    );
    _log.info(
      'Round 1: checking the ${plural(unreached.length, 'declaration', 'declarations')} no live code reaches…',
    );
    return unreached;
  }

  /// The removable findings no live reference reaches. [candidateOf] maps
  /// each finding to its candidate's index. [crossLib] sites count as
  /// references.
  DeadSpans sweep(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    CrossLibraryReferences crossLib,
    Map<UnusedDeclaration, int> candidateOf,
    String rootPath,
  ) {
    final spans = DeadSpans.of(candidateOf.keys, rootPath);
    final removable = {
      for (final MapEntry(key: finding, value: i) in candidateOf.entries)
        if (!finding.removalBlocked) i,
    };
    Iterable<int> containers(String path, Position position) => [
      for (final owner in spans.ownersOf(path, position)) candidateOf[owner]!,
    ];
    final uses = [
      for (final i in removable) ...[
        for (final loc in refsByCandidate[i])
          if (_classifier.classify(candidates[i], [loc], .empty) == .used)
            (
              target: i,
              containers: containers(
                SourceIndex.pathOf(loc.uri),
                loc.range.start,
              ),
            ),
        for (final usage in crossLib.recoveredUsages(candidates[i]))
          (
            target: i,
            containers: containers(
              usage.path,
              Position(line: usage.line, character: usage.character),
            ),
          ),
      ],
    ];
    final dead = unreached(removable, uses);
    return DeadSpans.of([
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
                if (!deadSpans.covers(
                  SourceIndex.pathOf(loc.uri),
                  loc.range.start,
                ))
                  loc,
            ],
        ];

  /// The findings in [deadSpans] that contain a reference to [candidate], in
  /// source order.
  List<DeadReferrer> onlyReferencedFrom(
    Candidate candidate,
    List<Location> refs,
    DeadSpans deadSpans,
  ) {
    if (deadSpans.isEmpty) {
      return const [];
    }
    final owners = <UnusedDeclaration>[];
    for (final loc in refs) {
      if (_classifier.isSelfReference(candidate, loc)) {
        continue;
      }
      final owner = deadSpans.ownerOf(
        SourceIndex.pathOf(loc.uri),
        loc.range.start,
      );
      if (owner != null && !owners.any((seen) => identical(seen, owner))) {
        owners.add(owner);
      }
    }
    owners.sort(compareByLocation);
    return [
      for (final owner in owners)
        (
          qualifiedName: owner.qualifiedName,
          filePath: owner.filePath,
          line: owner.line,
        ),
    ];
  }
}
