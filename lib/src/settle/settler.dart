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
import 'package:ciach/src/settle/superclasses.dart';
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

/// What one round settles.
typedef _Verdicts = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
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
    required Verdict verdict,
  }) : _files = files,
       _freezed = freezed,
       _classifier = classifier,
       _verdict = verdict;

  final FinderOptions options;
  final ResolvedFiles _files;
  final FreezedUnions _freezed;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;

  late final _clauseOnly = ClauseOnlyTypes(
    syntax: _files,
    classifier: _classifier,
    verdict: _verdict,
  );

  late final _transitive = TransitiveSweep(
    classifier: _classifier,
    verdict: _verdict,
  );

  late final _variableCuts = VariableCuts(_files);

  late final _wholeTypes = WholeTypes(verdict: _verdict);

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
    _Verdicts settled;
    Map<UnusedDeclaration, int> candidateOf;
    for (var round = 1; ; round++) {
      final result = _round(
        candidates,
        refsByCandidate,
        TransitiveSweep.liveRefs(refsByCandidate, deadSpans),
        deadSpans,
        overrides,
        scannedPaths,
        rootPath,
      );
      settled = result.settled;
      candidateOf = result.candidateOf;
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
      unused: settled.unused.sorted(compareByLocation),
      docOnly: settled.docOnly.sorted(compareByLocation),
      emptied: emptiedContainers(candidates, candidateOf, rootPath),
    );
  }

  /// One round, classifying from [liveRefs], with each unused finding's
  /// candidate index. [refsByCandidate] still holds the references into
  /// [deadSpans], for [DeadSpans.referrersAmong].
  ({_Verdicts settled, Map<UnusedDeclaration, int> candidateOf}) _round(
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

    final deadClassNames = _deadClassNames(candidates, statuses);

    final safety = RemoveSafety.analyze(
      _files,
      candidates,
      statuses,
      liveRefs,
      deadClassNames,
      (cls) => needsSuperArguments(_files, cls),
    );

    // `--remove` keeps a type that only doc comments mention, and its members.
    final docOnlyTypes = [
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .docOnly && candidate.isType) candidate,
    ];

    final reported = <int>{
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .unused &&
            !_verdict.isSuppressed(
              candidate,
              i,
              freezedUnionArms,
              deadClassNames,
              safety,
            ))
          i,
    };

    final reportOnlyTypes = _wholeTypes.reportOnly(
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
      kept: .of([
        for (final type in docOnlyTypes) _verdict.finding(type, rootPath),
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
    // A type in [reportOnlyTypes] and its members are left out:
    // [WholeTypes.report] reports the type once. So is an extension that a
    // live member keeps in use.
    final docOnly = [
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .docOnly &&
            !reportOnlyTypes.containsKey(candidate.key) &&
            !reportOnlyTypes.containsKey(candidate.containerKey) &&
            !(candidate.isExtension &&
                safety.extensionsWithLiveMembers.contains(candidate.key)))
          _verdict.finding(candidate, rootPath),
    ];
    // Make the fields and variables `--remove` can't cut out report-only now,
    // so that the next `--transitive` round keeps alive what they reference,
    // and a class that keeps one isn't listed as left empty.
    final unused = candidateOf.keys.toList();
    final cut = _variableCuts.withCuts(unused, rootPath);
    final cutCandidateOf = {
      for (final (k, finding) in cut.indexed) finding: candidateOf[unused[k]]!,
    };
    // Members of a type reported once as report-only aren't reported, so
    // `--remove` must not count them as removed.
    final removable = removableIndices(cutCandidateOf)
        .whereNot(
          (i) => reportOnlyTypes.containsKey(candidates[i].containerKey),
        )
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
    final findings = _withoutEnclosedInDead(
      _wholeTypes.report(
        {...cutCandidateOf, ...clauseOnly},
        candidates,
        reportOnlyTypes,
        _removableBefore,
        rootPath,
      ),
      deadSpans,
      rootPath,
    );
    return (
      settled: (unused: findings.keys.toList(), docOnly: docOnly),
      candidateOf: findings,
    );
  }

  /// [candidateOf] less each member reported only because its class is
  /// unused. Removing the class removes the member, so the member is not
  /// reported separately.
  static Map<UnusedDeclaration, int> _withoutEnclosedInDead(
    Map<UnusedDeclaration, int> candidateOf,
    DeadSpans deadSpans,
    String rootPath,
  ) {
    if (deadSpans.isEmpty) {
      return candidateOf;
    }
    final removable = DeadSpans.of(candidateOf.keys, rootPath);
    return .fromEntries(
      candidateOf.entries.whereNot(
        (entry) =>
            entry.key.onlyReferencedFrom.isNotEmpty &&
            removable.enclosesInAnother(entry.key, rootPath),
      ),
    );
  }

  /// Names of classes flagged unused, per file. A whole dead class is removed
  /// as one node, taking its own constructor(s) with it, so those constructors
  /// must not also be reported (or removed) on their own.
  static Map<String, Set<String>> _deadClassNames(
    List<Candidate> candidates,
    List<RefStatus> statuses,
  ) => candidates
      .whereIndexed(
        (i, candidate) => statuses[i] == .unused && candidate.isClassOrMixin,
      )
      .groupFoldBy<String, Set<String>>(
        (cls) => cls.path,
        (names, cls) => (names ?? {})..add(cls.name),
      );

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
