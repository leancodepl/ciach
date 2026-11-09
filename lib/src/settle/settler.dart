import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/clause_only_types.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/emptied_containers.dart';
import 'package:ciach/src/settle/overrides.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/removable.dart';
import 'package:ciach/src/settle/remove_safety.dart';
import 'package:ciach/src/settle/transitive.dart';
import 'package:ciach/src/settle/variable_cuts.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/settle/whole_types.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

/// What a run reports, sorted by location.
typedef Settled = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
  List<EmptiedContainer> emptied,
});

/// From references to findings: settles each candidate's verdict — classifies
/// it, applies the conventions and remove-safety, couples overrides — and
/// builds the sorted report. With `transitive`, every candidate starts dead
/// and only what live code reaches is revived (see [TransitiveSweep]), so dead
/// cycles are reported too. Each round then settles the verdicts, and what a
/// round keeps revives what it reaches, until the dead set stops changing.
/// Rounds reuse the references and the cached override lookups.
final class Settler {
  Settler({
    required this.options,
    required ResolvedFiles files,
    required FreezedUnions freezed,
    required ReferenceClassifier classifier,
  }) : _files = files,
       _freezed = freezed,
       _classifier = classifier;

  final FinderOptions options;
  final ResolvedFiles _files;
  final FreezedUnions _freezed;
  final ReferenceClassifier _classifier;
  late final _verdict = Verdict(options: options, classifier: _classifier);

  late final _clauseOnly = ClauseOnlyTypes(
    syntax: _files,
    classifier: _classifier,
    verdict: _verdict,
  );

  late final _transitive = TransitiveSweep(
    classifier: _classifier,
    verdict: _verdict,
  );

  /// Candidates an earlier round found removable. A group guard (every value
  /// of an enum, every constructor of a class) doesn't block them later: the
  /// members that joined the group since stay blocked, so the group isn't
  /// emptied, and removing these alone was safe. Otherwise blocking one would
  /// revive what only it referenced, unblock it, and so on every other round.
  final _removableBefore = <int>{};

  /// Only a guard: each round deletes more of a finite source than the last,
  /// so the rounds end on their own.
  static const _maxRounds = 16;

  /// The findings for [candidates], from their [refsByCandidate].
  Settled settle(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) {
    final overrides = OverrideRemovals(
      _files,
      scannedPaths: scannedPaths,
      rootPath: rootPath,
    );

    var deadSpans = options.transitive
        ? _transitive.allUnreached(candidates, refsByCandidate, rootPath)
        : DeadSpans.empty;
    ({List<UnusedDeclaration> docOnly, Map<UnusedDeclaration, int> candidateOf})
    result;
    for (var round = 1; ; round++) {
      result = _round(
        candidates,
        refsByCandidate,
        TransitiveSweep.liveRefs(refsByCandidate, deadSpans),
        deadSpans,
        overrides,
        scannedPaths,
        rootPath,
      );
      if (!options.transitive) {
        break;
      }
      final next = _transitive.sweep(
        candidates,
        refsByCandidate,
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
    return (
      unused: result.candidateOf.keys.sorted(compareByLocation),
      docOnly: result.docOnly.sorted(compareByLocation),
      emptied: emptiedContainers(candidates, result.candidateOf, rootPath),
    );
  }

  /// One round, classifying from [liveRefs], with each unused finding's
  /// candidate index. [refsByCandidate] still holds the references into
  /// [deadSpans], for [DeadSpans.referrersAmong].
  ({List<UnusedDeclaration> docOnly, Map<UnusedDeclaration, int> candidateOf})
  _round(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    DeadSpans deadSpans,
    OverrideRemovals overrides,
    Set<String> scannedPaths,
    String rootPath,
  ) {
    final statuses = [
      for (final (i, candidate) in candidates.indexed)
        _classifier.classify(candidate, liveRefs[i]),
    ];

    // A deser-only union arm reads zero references but is a live serialization
    // member.
    final freezedUnionArms = _freezed.deserializationOnlyArms(
      candidates,
      statuses,
    );

    final safety = RemoveSafety.analyze(_files, candidates, statuses, liveRefs);

    final reported = <int>{
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .unused &&
            !_verdict.isSuppressed(candidate, i, freezedUnionArms, safety))
          i,
    };

    final reportOnly = reportOnlyTypes(
      candidates,
      statuses,
      reported,
      _removableBefore,
      safety,
    );

    // Remove a dead member's overrides with it. If an override has to stay,
    // for example because it is in a doc-only type, keep the member too.
    final overridden = overrides.couple(
      candidates,
      [
        for (final index in reported)
          if (_verdict.canBeOverridden(candidates[index])) index,
      ],
      // `--remove` keeps a type that only doc comments mention, and its
      // members.
      kept: .of([
        for (final (i, candidate) in candidates.indexed)
          if (statuses[i] == .docOnly && candidate.isType)
            _verdict.finding(candidate, rootPath),
      ], rootPath),
    );

    final candidateOf = {
      for (final i in reported)
        _unusedFinding(
          i,
          candidates: candidates,
          refsByCandidate: refsByCandidate,
          liveRefs: liveRefs,
          overridden: overridden[i],
          safety: safety,
          deadSpans: deadSpans,
          rootPath: rootPath,
        ): i,
    };
    // A type in [reportOnly] and its members are left out: [reportWholeTypes]
    // reports the type once. So is an extension that a live member keeps in
    // use.
    final docOnly = [
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .docOnly &&
            !reportOnly.containsKey(candidate.key) &&
            !reportOnly.containsKey(candidate.containerKey) &&
            !(candidate.isExtension &&
                safety.extensionsWithLiveMembers.contains(candidate.key)))
          _verdict.finding(candidate, rootPath),
    ];
    // Make the fields and variables `--remove` can't cut out report-only now,
    // so that the next `--transitive` round keeps alive what they reference,
    // and a class that keeps one isn't listed as left empty.
    final cutCandidateOf = withVariableCuts(_files, candidateOf, rootPath);
    // Members of a type reported once as report-only aren't reported, so
    // `--remove` must not count them as removed.
    final removable = removableIndices(cutCandidateOf)
        .whereNot((i) => reportOnly.containsKey(candidates[i].containerKey))
        .toSet();
    _removableBefore.addAll(removable);
    final clauseOnly = _clauseOnly.findings(
      candidates,
      statuses,
      refsByCandidate,
      liveRefs,
      removable,
      deadSpans,
      scannedPaths,
      rootPath,
    );
    return (
      docOnly: docOnly,
      candidateOf: _withoutEnclosedInDead(
        reportWholeTypes(
          _verdict,
          {...cutCandidateOf, ...clauseOnly},
          candidates,
          reportOnly,
          _removableBefore,
          rootPath,
        ),
        rootPath,
      ),
    );
  }

  /// [candidateOf] less each member reported only because its class is
  /// unused. Removing the class removes the member, so the member is not
  /// reported separately.
  static Map<UnusedDeclaration, int> _withoutEnclosedInDead(
    Map<UnusedDeclaration, int> candidateOf,
    String rootPath,
  ) {
    final removable = DeadSpans.of(candidateOf.keys, rootPath);
    return .fromEntries(
      candidateOf.entries.whereNot(
        (entry) =>
            entry.key.onlyReferencedFrom.isNotEmpty &&
            removable.enclosesInAnother(entry.key, rootPath),
      ),
    );
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
    final pairedState = candidate.isClassOrMixin
        ? _files.pairedStateRemovals(
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
      onlyReferencedFrom: deadSpans.referrersAmong(
        _classifier.externalRefs(candidate, refsByCandidate[i]),
      ),
    );
  }
}
