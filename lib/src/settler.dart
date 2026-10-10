import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/overrides.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/superclasses.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/verdict.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

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
/// and only what live code reaches is revived (see [unreached]), so dead
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
  }) : _sources = sources,
       _freezed = freezed,
       _classifier = classifier,
       _verdict = verdict;

  final FinderOptions options;
  final SourceIndex _sources;
  final FreezedUnions _freezed;
  final ReferenceClassifier _classifier;
  final Verdict _verdict;

  /// Names the cross-library recovery has already probed.
  final _probedNames = <String>{};

  /// Override lookups by candidate index, cached across rounds.
  final _overridesByMember = <int, OverriddenMember>{};

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
        ? _unreachedCandidates(candidates, refsByCandidate, rootPath)
        : DeadSpans.empty;
    Settled settled;
    for (var round = 1; ; round++) {
      final liveRefs = _liveRefs(refsByCandidate, deadSpans);
      crossLib = crossLib.merged(
        await _recoverCrossLibraryRefs(client, candidates, liveRefs),
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
      final next = _sweep(
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

  /// The spans of every candidate no live code reaches, all of them assumed
  /// dead to begin with.
  DeadSpans _unreachedCandidates(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final allDead = {
      for (var i = 0; i < candidates.length; i++)
        _verdict.finding(candidates[i], rootPath): i,
    };
    final unreached = _sweep(
      candidates,
      refsByCandidate,
      .empty,
      allDead,
      rootPath,
    );
    _log.info(
      'Round 1: checking the '
      '${plural(unreached.length, 'declaration', 'declarations')} no live '
      'code reaches…',
    );
    return unreached;
  }

  /// The removable findings no live reference reaches. [candidateOf] maps
  /// each finding to its candidate's index. [crossLib] sites count as
  /// references.
  DeadSpans _sweep(
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
  List<List<Location>> _liveRefs(
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

  /// One round, classifying from [liveRefs], with each unused finding's
  /// candidate index. [refsByCandidate] still holds the references into
  /// [deadSpans], for [_onlyReferencedFrom].
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

    final recovered = _recoveredWarnings(
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
    final overridden = await _coupleOverrides(candidates, reported, overrides);

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
      onlyReferencedFrom: _onlyReferencedFrom(
        candidate,
        refsByCandidate[i],
        deadSpans,
      ),
    );
  }

  /// The findings in [deadSpans] that contain a reference to [candidate], in
  /// source order.
  List<DeadReferrer> _onlyReferencedFrom(
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

  /// The overrides to delete along with each reported dead member, by
  /// candidate index. Members with nothing to say are left out.
  Future<Map<int, OverriddenMember>> _coupleOverrides(
    List<Candidate> candidates,
    Set<int> reported,
    OverrideRemovals overrides,
  ) async {
    final members = [
      for (final index in reported)
        if (_verdict.canBeOverridden(candidates[index])) index,
    ];
    final unchecked = members.whereNot(_overridesByMember.containsKey).toList();
    await _checkOverrides(unchecked, candidates, overrides);
    final byCandidate = <int, OverriddenMember>{};
    var coupled = 0;
    var couplingMembers = 0;
    var blocked = 0;
    for (final index in members) {
      final result = _overridesByMember[index]!;
      if (result.removals.isEmpty && !result.blocked) {
        continue;
      }
      byCandidate[index] = result;
      coupled += result.removals.length;
      if (result.removals.isNotEmpty) {
        couplingMembers++;
      }
      if (result.blocked) {
        blocked++;
      }
    }
    if (coupled > 0) {
      _log.fine(
        'Coupling ${plural(coupled, 'override', 'overrides')} to '
        '${plural(couplingMembers, 'dead member', 'dead members')}.',
      );
    }
    if (blocked > 0) {
      _log.fine(
        '${plural(blocked, 'dead member', 'dead members')} ${pluralWord(blocked, 'is', 'are')} '
        'overridden where --remove cannot follow; left in place.',
      );
    }
    return byCandidate;
  }

  Future<void> _checkOverrides(
    List<int> unchecked,
    List<Candidate> candidates,
    OverrideRemovals overrides,
  ) async {
    if (unchecked.isEmpty) {
      return;
    }
    _log.info(
      'Checking ${plural(unchecked.length, 'dead member', 'dead members')} for overrides…',
    );
    final results = await mapPooled(
      unchecked,
      options.concurrency,
      (index) => overrides.of(candidates[index]),
    );
    for (final (i, index) in unchecked.indexed) {
      _overridesByMember[index] = results[i];
    }
  }

  /// One warning per declaration the secondary check kept alive: it had no
  /// reported references outside itself, yet a use resolved back to it.
  List<RecoveredReference> _recoveredWarnings(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    CrossLibraryReferences crossLib,
    String rootPath,
    String analysisRoot,
  ) {
    final warnings = <RecoveredReference>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (_classifier.externalRefs(candidate, refsByCandidate[i]).isNotEmpty ||
          candidate.symbol.kind == .class$ ||
          candidate.isExtension) {
        continue;
      }
      final usage = crossLib.recoveredUsage(candidate);
      if (usage == null) {
        continue;
      }
      final start = candidate.symbol.selectionRange.start;
      warnings.add(
        RecoveredReference(
          name: candidate.symbol.declarationName(candidate.container),
          container: candidate.container,
          filePath: relativePosix(candidate.path, rootPath),
          line: start.line + 1,
          column: start.character + 1,
          usageFilePath: relativeUsagePosix(usage.path, rootPath, analysisRoot),
          usageLine: usage.line + 1,
          usageColumn: usage.character + 1,
        ),
      );
    }
    warnings.sort((a, b) {
      final byFile = a.filePath.compareTo(b.filePath);
      if (byFile != 0) {
        return byFile;
      }
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.column.compareTo(b.column);
    });
    return warnings;
  }

  /// Runs the secondary definition check for the candidates with no reference
  /// outside their own span — the potential false positives. Names probed in an
  /// earlier round are skipped.
  Future<CrossLibraryReferences> _recoverCrossLibraryRefs(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> liveRefs,
  ) {
    final emptyRefNames = <String>{
      for (var i = 0; i < candidates.length; i++)
        if (_classifier.externalRefs(candidates[i], liveRefs[i]).isEmpty &&
            candidates[i].symbol.kind != .class$ &&
            !candidates[i].isExtension) ...[
          _simpleName(candidates[i].symbol.name),
          // An unnamed constructor is spelled by the class name at an
          // ordinary `Foo(…)` site but as `new` at a dot-shorthand one
          // (`.new(…)`), so probe for both spellings.
          candidates[i].symbol.declarationName(candidates[i].container),
        ],
    }..removeAll(_probedNames);
    if (emptyRefNames.isEmpty) {
      return .value(.empty);
    }
    _probedNames.addAll(emptyRefNames);
    _log.info('Recovering cross-library references…');
    return CrossLibraryReferences.resolve(
      client: client,
      sources: _sources,
      candidates: candidates,
      emptyRefNames: emptyRefNames,
      concurrency: options.concurrency,
    );
  }

  /// The last-segment name — `bar` for a constructor reported as `Foo.bar` —
  /// which is the identifier a usage site spells.
  static String _simpleName(String name) =>
      name.contains('.') ? name.split('.').last : name;
}
