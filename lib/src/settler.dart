import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/cross_library_recovery.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:ciach/src/finder_options.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/overrides.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/superclasses.dart';
import 'package:ciach/src/transitive_sweep.dart';
import 'package:ciach/src/verdict.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.finder');

/// What a run reports, sorted by location.
typedef Settled = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
  List<RecoveredReference> recovered,
});

/// From references to findings: settles each candidate's verdict — classifies
/// it, applies the conventions and remove-safety, couples overrides — and
/// builds the sorted report. With `transitive`, every candidate starts dead
/// and only what live code reaches is revived (see [TransitiveSweep]), so
/// dead cycles are reported too. Each round then settles the verdicts, and
/// what a round keeps revives what it reaches, until the dead set stops
/// changing. Rounds reuse the fetched references and cached override lookups,
/// and probe only the names a round newly leaves unreferenced.
final class Settler {
  Settler({
    required this.options,
    required SourceIndex sources,
    required FreezedUnions freezed,
    required ReferenceClassifier classifier,
    required Verdict verdict,
  }) : _sources = sources,
       _freezed = freezed,
       _classifier = classifier,
       _verdict = verdict,
       _sweep = TransitiveSweep(classifier: classifier, verdict: verdict),
       _recovery = CrossLibraryRecovery(
         sources: sources,
         classifier: classifier,
         concurrency: options.concurrency,
       );

  final FinderOptions options;
  final SourceIndex _sources;
  final FreezedUnions _freezed;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;
  final TransitiveSweep _sweep;
  final CrossLibraryRecovery _recovery;

  /// Candidates an earlier round found removable. A group guard (every value
  /// of an enum, every constructor of a class) doesn't block them later: the
  /// members that joined the group since stay blocked, so the group isn't
  /// emptied, and removing these alone was safe. Otherwise blocking one would
  /// revive what only it referenced, unblock it, and so on every other round.
  final _removableBefore = <int>{};

  /// Only a guard: each round deletes more of a finite source than the last,
  /// so the rounds end on their own.
  static const _maxRounds = 16;

  /// The findings for [candidates], from the server's [refsByCandidate].
  Future<Settled> settle(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate, {
    required Set<String> scannedPaths,
    required String rootPath,
    required String analysisRoot,
  }) async {
    final superclasses = SuperclassChecks(client);
    final overrides = OverrideRemovals(
      client,
      _sources,
      scannedPaths: scannedPaths,
      rootPath: rootPath,
    );

    var crossLib = CrossLibraryReferences.empty;
    var deadSpans = options.transitive
        ? _sweep.unreachedCandidates(candidates, refsByCandidate, rootPath)
        : DeadSpans.empty;
    Settled settled;
    for (var round = 1; ; round++) {
      final liveRefs = TransitiveSweep.liveRefs(refsByCandidate, deadSpans);
      crossLib = crossLib.merged(
        await _recovery.recover(client, candidates, liveRefs),
      );
      final result = await _round(
        candidates,
        refsByCandidate,
        liveRefs,
        crossLib.whereNot(deadSpans.covers),
        deadSpans,
        superclasses,
        overrides,
        rootPath,
        analysisRoot,
      );
      settled = result.settled;
      if (!options.transitive) {
        break;
      }
      final next = _sweep.sweep(
        candidates,
        refsByCandidate,
        crossLib,
        result.candidateOf,
        rootPath,
      );
      if (next.sameAs(deadSpans)) {
        if (round > 1) {
          _log.fine('Settled after ${plural(round, 'round', 'rounds')}.');
        }
        break;
      }
      if (round == _maxRounds) {
        _log.warning(
          'Stopping after $_maxRounds rounds; later rounds may find more.',
        );
        break;
      }
      _log.info(
        'Round ${round + 1}: checking what only the '
        '${plural(next.length, 'removable finding', 'removable findings')} referenced…',
      );
      deadSpans = next;
    }
    if (settled.recovered.isNotEmpty) {
      _log.fine(
        'Kept ${plural(settled.recovered.length, 'declaration', 'declarations')} the reference '
        'search called unused: the definition check found a use for each.',
      );
    }
    return (
      unused: settled.unused.sorted(compareByLocation),
      docOnly: settled.docOnly.sorted(compareByLocation),
      recovered: settled.recovered,
    );
  }

  /// One round, classifying from [liveRefs], with each unused finding's
  /// candidate index. [refsByCandidate] still holds the references into
  /// [deadSpans], for [TransitiveSweep.onlyReferencedFrom].
  Future<({Settled settled, Map<UnusedDeclaration, int> candidateOf})> _round(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    CrossLibraryReferences crossLib,
    DeadSpans deadSpans,
    SuperclassChecks superclasses,
    OverrideRemovals overrides,
    String rootPath,
    String analysisRoot,
  ) async {
    final statuses = [
      for (var i = 0; i < candidates.length; i++)
        _classifier.classify(candidates[i], liveRefs[i], crossLib),
    ];

    final recovered = _recovery.warnings(
      candidates,
      liveRefs,
      crossLib,
      rootPath,
      analysisRoot,
    );

    // A deser-only union arm reads zero references but is a live serialization
    // member.
    final freezedUnionArms = _freezed.deserializationOnlyArms(
      candidates,
      statuses,
      _sources,
    );

    final deadClassNames = _deadClassNames(candidates, statuses);

    final safety = await RemoveSafety.analyze(
      _sources,
      candidates,
      statuses,
      liveRefs,
      deadClassNames,
      superclasses.needsConstructorArguments,
    );

    final reported = <int>{
      for (var i = 0; i < candidates.length; i++)
        if (statuses[i] == .unused &&
            !_verdict.isSuppressed(
              candidates[i],
              i,
              freezedUnionArms,
              deadClassNames,
              safety,
            ))
          i,
    };

    // Couple a dead member's overrides to its removal, or let one that has to
    // stay block it.
    final overridden = await overrides.couple(candidates, [
      for (final index in reported)
        if (_verdict.canBeOverridden(candidates[index])) index,
    ], concurrency: options.concurrency);

    final unused = <UnusedDeclaration>[];
    final candidateOf = <UnusedDeclaration, int>{};
    final docOnly = <UnusedDeclaration>[];
    for (final (i, candidate) in candidates.indexed) {
      switch (statuses[i]) {
        case .unused when reported.contains(i):
          final finding = _unusedFinding(
            i,
            candidates: candidates,
            refsByCandidate: refsByCandidate,
            liveRefs: liveRefs,
            overridden: overridden[i],
            safety: safety,
            deadSpans: deadSpans,
            rootPath: rootPath,
          );
          unused.add(finding);
          candidateOf[finding] = i;
          if (!finding.removalBlocked) {
            _removableBefore.add(i);
          }
        case .docOnly:
          docOnly.add(_verdict.finding(candidate, rootPath));
        case .unused || .used:
          break;
      }
    }

    // A member reported only because its class died is removed with the class,
    // so it isn't reported on its own.
    if (deadSpans.isNotEmpty) {
      final removable = DeadSpans.of(unused, rootPath);
      unused.removeWhere(
        (finding) =>
            finding.onlyReferencedFrom.isNotEmpty &&
            removable.enclosesInAnother(finding, rootPath),
      );
    }

    return (
      settled: (unused: unused, docOnly: docOnly, recovered: recovered),
      candidateOf: {
        for (final finding in unused) finding: candidateOf[finding]!,
      },
    );
  }

  /// Names of classes flagged unused, per file. A whole dead class is removed
  /// as one node, taking its own constructor(s) with it, so those constructors
  /// must not also be reported (or removed) on their own.
  static Map<String, Set<String>> _deadClassNames(
    List<Candidate> candidates,
    List<RefStatus> statuses,
  ) {
    final deadClassNames = <String, Set<String>>{};
    for (final (i, candidate) in candidates.indexed) {
      if (statuses[i] == .unused && candidate.symbol.kind == .class$) {
        deadClassNames
            .putIfAbsent(candidate.path, () => <String>{})
            .add(candidate.symbol.name);
      }
    }
    return deadClassNames;
  }

  UnusedDeclaration _unusedFinding(
    int i, {
    required List<Candidate> candidates,
    required List<List<Location>> refsByCandidate,
    required List<List<Location>> liveRefs,
    required OverriddenMember? overridden,
    required RemoveSafety safety,
    required DeadSpans deadSpans,
    required String rootPath,
  }) {
    final candidate = candidates[i];
    final refs = liveRefs[i];
    final blockedByOverride = overridden?.blocked ?? false;
    final pairedState = candidate.symbol.kind == .class$
        ? _sources.pairedStateRemovals(
            candidate,
            refs,
            candidates,
            liveRefs,
            rootPath,
          )
        : null;
    final blockedByState = pairedState?.blocked ?? false;
    return _verdict.finding(
      candidate,
      rootPath,
      coupledRemovals:
          pairedState?.removals ?? overridden?.removals ?? const [],
      removalBlocked:
          _verdict.isRemovalBlocked(
            candidate,
            refs,
            safety,
            groupGuards: !_removableBefore.contains(i),
          ) ||
          blockedByOverride ||
          blockedByState,
      hint:
          _verdict.hintFor(candidate) ??
          (blockedByOverride ? Verdict.overriddenHint : null) ??
          (blockedByState ? Verdict.pairedStateHint : null),
      onlyReferencedFrom: _sweep.onlyReferencedFrom(
        candidate,
        refsByCandidate[i],
        deadSpans,
      ),
    );
  }
}
