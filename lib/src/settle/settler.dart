import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/fetch/cross_library_refs.dart';
import 'package:ciach/src/fetch/member_probe.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/clause_only_types.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/settle/emptied_containers.dart';
import 'package:ciach/src/settle/overrides.dart';
import 'package:ciach/src/settle/probed_references.dart';
import 'package:ciach/src/settle/recovery.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/removable.dart';
import 'package:ciach/src/settle/remove_safety.dart';
import 'package:ciach/src/settle/superclasses.dart';
import 'package:ciach/src/settle/transitive.dart';
import 'package:ciach/src/settle/variable_cuts.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/settle/whole_types.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.finder');

/// What a run reports, sorted by location.
typedef Settled = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
  List<RecoveredReference> recovered,
  List<EmptiedContainer> emptied,
});

/// What one round settles.
typedef _Verdicts = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
  List<RecoveredReference> recovered,
});

/// From references to findings: settles each candidate's verdict — classifies
/// it, applies the conventions and remove-safety, couples overrides — and
/// builds the sorted report. With `transitive`, every candidate starts dead
/// and only what live code reaches is revived (see [TransitiveSweep]), so dead
/// cycles are reported too. Each round then settles the verdicts, and what a
/// round keeps revives what it reaches, until the dead set stops changing.
/// Rounds reuse the fetched references and cached override lookups, and probe
/// only the names a round newly leaves unreferenced.
final class Settler {
  Settler({
    required this.options,
    required SourceIndex sources,
    required FreezedUnions freezed,
    required ReferenceClassifier classifier,
    required Verdict verdict,
    required ReferenceFetch fetch,
  }) : _sources = sources,
       _freezed = freezed,
       _classifier = classifier,
       _verdict = verdict,
       _fetch = fetch;

  final FinderOptions options;
  final SourceIndex _sources;
  final FreezedUnions _freezed;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;
  final ReferenceFetch _fetch;

  late final _recovery = ReferenceRecovery(
    sources: _sources,
    classifier: _classifier,
    concurrency: options.concurrency,
  );

  late final _clauseOnly = ClauseOnlyTypes(
    sources: _sources,
    classifier: _classifier,
    verdict: _verdict,
    fetch: _fetch,
  );

  late final _transitive = TransitiveSweep(
    classifier: _classifier,
    verdict: _verdict,
  );

  late final _variableCuts = VariableCuts(fetch: _fetch, sources: _sources);

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

  /// The findings for [candidates], from the server's [refsByCandidate].
  /// The references of the candidates [probe] found used are only the uses it
  /// found, which a round completes before calling one dead.
  Future<Settled> settle(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate, {
    required Set<String> scannedPaths,
    required String rootPath,
    required String analysisRoot,
    MemberProbe? probe,
  }) async {
    final superclasses = SuperclassChecks(client);
    final overrides = OverrideRemovals(
      client,
      _sources,
      scannedPaths: scannedPaths,
      rootPath: rootPath,
    );

    final probedRefs = ProbedReferences(_fetch, probe);
    Future<DeadSpans> completed(DeadSpans Function() spans) =>
        probedRefs.completeIn(
          spans,
          client,
          candidates,
          refsByCandidate,
          rootPath: rootPath,
        );

    var crossLib = CrossLibraryReferences.empty;
    var deadSpans = options.transitive
        ? await completed(
            () =>
                _transitive.allUnreached(candidates, refsByCandidate, rootPath),
          )
        : DeadSpans.empty;
    _Verdicts settled;
    Map<UnusedDeclaration, int> candidateOf;
    for (var round = 1; ; round++) {
      final liveRefs = TransitiveSweep.liveRefs(refsByCandidate, deadSpans);
      crossLib = crossLib.merged(
        await _recovery.recover(client, candidates, liveRefs),
      );
      final result = await _round(
        client,
        candidates,
        refsByCandidate,
        liveRefs,
        crossLib.whereNot(deadSpans.covers),
        deadSpans,
        superclasses,
        overrides,
        scannedPaths,
        rootPath,
        analysisRoot,
      );
      settled = result.settled;
      candidateOf = result.candidateOf;
      if (!options.transitive) {
        break;
      }
      final next = await completed(
        () => _transitive.sweep(
          candidates,
          refsByCandidate,
          crossLib,
          result.candidateOf,
          rootPath,
        ),
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
      emptied: emptiedContainers(candidates, candidateOf, rootPath),
    );
  }

  /// One round, classifying from [liveRefs], with each unused finding's
  /// candidate index. [refsByCandidate] still holds the references into
  /// [deadSpans], for [DeadSpans.referrersAmong].
  Future<({_Verdicts settled, Map<UnusedDeclaration, int> candidateOf})> _round(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    CrossLibraryReferences crossLib,
    DeadSpans deadSpans,
    SuperclassChecks superclasses,
    OverrideRemovals overrides,
    Set<String> scannedPaths,
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

    // `--remove` keeps a type that only doc comments mention, and its members.
    final docOnlyTypes = [
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .docOnly && candidate.isType) candidate,
    ];

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

    final reportOnlyTypes = _wholeTypes.reportOnly(
      candidates,
      statuses,
      reported,
      _removableBefore,
      safety,
    );

    // Remove a dead member's overrides with it. If an override has to stay,
    // for example because it is in a doc-only type, keep the member too.
    final overridden = await overrides.couple(
      candidates,
      [
        for (final index in reported)
          if (_verdict.canBeOverridden(candidates[index])) index,
      ],
      kept: DeadSpans.of([
        for (final type in docOnlyTypes) _verdict.finding(type, rootPath),
      ], rootPath),
      concurrency: options.concurrency,
    );

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
        // A doc-only type reported once instead of its members, or one of its
        // members: [WholeTypes.report] reports the type.
        case .docOnly
            when reportOnlyTypes.containsKey(candidate.key) ||
                reportOnlyTypes.containsKey(candidate.containerKey):
          break;
        case .docOnly:
          docOnly.add(_verdict.finding(candidate, rootPath));
        case .unused || .used:
          break;
      }
    }
    // Make the fields and variables `--remove` can't cut out report-only now,
    // so that the next `--transitive` round keeps alive what they reference,
    // and a class that keeps one isn't listed as left empty.
    final cut = await _variableCuts.withCuts(client, unused, rootPath);
    final cutCandidateOf = {
      for (final (k, finding) in cut.indexed) finding: candidateOf[unused[k]]!,
    };
    // Members of a type reported once as report-only aren't reported, so
    // `--remove` must not count them as removed.
    final removable = removableIndices(cutCandidateOf)
      ..removeWhere(
        (i) => reportOnlyTypes.containsKey(candidates[i].containerKey),
      );
    _removableBefore.addAll(removable);
    for (final (i, finding) in await _clauseOnly.findings(
      client,
      candidates,
      statuses,
      refsByCandidate,
      liveRefs,
      removable,
      deadSpans,
      scannedPaths,
      rootPath,
    )) {
      cut.add(finding);
      cutCandidateOf[finding] = i;
    }
    _wholeTypes.report(
      cut,
      candidates,
      cutCandidateOf,
      reportOnlyTypes,
      _removableBefore,
      rootPath,
    );

    _dropEnclosedInDead(cut, deadSpans, rootPath);

    return (
      settled: (unused: cut, docOnly: docOnly, recovered: recovered),
      candidateOf: {
        for (final finding in cut) finding: cutCandidateOf[finding]!,
      },
    );
  }

  /// Removes from [unused] each member reported only because its class is
  /// unused. Removing the class removes the member, so the member is not
  /// reported separately.
  static void _dropEnclosedInDead(
    List<UnusedDeclaration> unused,
    DeadSpans deadSpans,
    String rootPath,
  ) {
    if (deadSpans.isEmpty) {
      return;
    }
    final removable = DeadSpans.of(unused, rootPath);
    unused.removeWhere(
      (finding) =>
          finding.onlyReferencedFrom.isNotEmpty &&
          removable.enclosesInAnother(finding, rootPath),
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
      onlyReferencedFrom: deadSpans.referrersAmong(
        _classifier.externalRefs(candidate, refsByCandidate[i]),
      ),
    );
  }
}
