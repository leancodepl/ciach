import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/clause_entries.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:ciach/src/declarator_cuts.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/overrides.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/superclasses.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/verdict.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, SymbolKind;

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
    _Verdicts settled;
    Map<UnusedDeclaration, int> candidateOf;
    for (var round = 1; ; round++) {
      final liveRefs = _liveRefs(refsByCandidate, deadSpans);
      crossLib = crossLib.merged(
        await _recoverCrossLibraryRefs(client, candidates, liveRefs),
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
      emptied: _emptiedContainers(candidates, candidateOf, rootPath),
    );
  }

  /// Returns the classes, mixins and extensions that `--remove` leaves with an
  /// empty body: each of their members is a removable finding in [candidateOf],
  /// but the declaration itself is not a finding, because other code still
  /// uses it.
  static List<EmptiedContainer> _emptiedContainers(
    List<Candidate> candidates,
    Map<UnusedDeclaration, int> candidateOf,
    String rootPath,
  ) {
    final removable = _removableIndices(candidateOf);
    final members = _removableMembers(candidates, removable);
    return [
      for (final MapEntry(key: container, value: (:outline, :removable))
          in members.entries)
        if (outline?.children.length == removable &&
            // An extension type keeps its representation field, like `value` in
            // `extension type Id(int value)`. The outline leaves that field
            // out, so the type would wrongly look emptied.
            outline!.element.kind != .extensionType)
          (
            filePath: relativePosix(container.path, rootPath),
            name: container.name,
          ),
    ]..sort(
      (a, b) => switch (a.filePath.compareTo(b.filePath)) {
        0 => a.name.compareTo(b.name),
        final byFile => byFile,
      },
    );
  }

  /// Returns, by key, each class, mixin or extension with a member in
  /// [removable]: its outline, and how many of its members are in [removable].
  static Map<DeclKey, ({Outline? outline, int removable})> _removableMembers(
    List<Candidate> candidates,
    Set<int> removable,
  ) => {
    for (final MapEntry(:key, value: members)
        in removable
            .map((i) => candidates[i])
            .groupListsBy((candidate) => candidate.containerKey)
            .entries)
      ?key: (
        outline: members.first.containerOutline,
        removable: members.length,
      ),
  };

  /// Returns [unused] with [UnusedDeclaration.cut] set on each removable field
  /// and top-level variable, both findings and coupled removals.
  ///
  /// It first fetches the selection ranges this needs, for these variables
  /// only. The cuts are worked out in one call, so two removed variables of
  /// one statement are cut as one. A finding whose own cut, or the cut of a
  /// variable coupled to it, can't be worked out becomes report-only, with
  /// [Verdict.noCutHint].
  Future<List<UnusedDeclaration>> _withCuts(
    LspClient client,
    List<UnusedDeclaration> unused,
    String rootPath,
  ) async {
    DeclaratorAt at(String filePath, int line, int column) => (
      path: absoluteUnder(filePath, rootPath),
      name: .new(line: line, character: column),
    );
    DeclaratorAt ofFinding(UnusedDeclaration finding) =>
        at(finding.filePath, finding.line - 1, finding.column - 1);
    DeclaratorAt ofCoupled(CoupledRemoval coupled) => at(
      coupled.filePath,
      coupled.range.startLine,
      coupled.range.startColumn,
    );
    bool isDeclarator(SymbolKind kind) => declaratorKinds.contains(kind);

    final removable = unused.whereNot((finding) => finding.removalBlocked);
    final declarators = [
      for (final finding in removable) ...[
        if (isDeclarator(finding.kind)) ofFinding(finding),
        for (final coupled in finding.coupledRemovals)
          if (isDeclarator(coupled.kind)) ofCoupled(coupled),
      ],
    ];
    await _fetch.fetchSelectionRanges(
      client,
      declarators.groupFoldBy(
        (declarator) => declarator.path,
        (names, declarator) => (names ?? <Position>{})..add(declarator.name),
      ),
    );
    await _fetch.fetchSelectionRanges(
      client,
      _sources.otherDeclaratorNames(declarators),
    );
    final cuts = _sources.declaratorCuts(declarators);
    UnusedDeclaration withCuts(UnusedDeclaration finding) {
      final cut = isDeclarator(finding.kind) ? cuts[ofFinding(finding)] : null;
      final coupledRemovals = [
        for (final coupled in finding.coupledRemovals)
          if (isDeclarator(coupled.kind))
            (
              filePath: coupled.filePath,
              kind: coupled.kind,
              range: coupled.range,
              fullRange: coupled.fullRange,
              cut: cuts[ofCoupled(coupled)],
            )
          else
            coupled,
      ];
      bool lacksCut(SymbolKind kind, DeclarationRange? cut) =>
          isDeclarator(kind) && cut == null;
      if (lacksCut(finding.kind, cut) ||
          coupledRemovals.any(
            (coupled) => lacksCut(coupled.kind, coupled.cut),
          )) {
        return finding.copyWith(removalBlocked: true, hint: Verdict.noCutHint);
      }
      return finding.copyWith(cut: cut, coupledRemovals: coupledRemovals);
    }

    return [
      for (final finding in unused)
        if (finding.removalBlocked) finding else withCuts(finding),
    ];
  }

  /// The candidate indices of the findings in [candidateOf] that `--remove`
  /// deletes.
  static Set<int> _removableIndices(Map<UnusedDeclaration, int> candidateOf) =>
      {
        for (final MapEntry(key: finding, value: i) in candidateOf.entries)
          if (!finding.removalBlocked) i,
      };

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
      'Round 1: checking the ${plural(unreached.length, 'declaration', 'declarations')} no live code reaches…',
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
    final removable = _removableIndices(candidateOf);
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
    // Removing a dead type also removes its clause entries. Keep those entries
    // as references here, so the next round reports the type as used only in
    // clauses and not as unused.
    return DeadSpans.of(
      [
        for (final MapEntry(key: finding, value: i) in candidateOf.entries)
          if (dead.contains(i)) finding,
      ],
      rootPath,
      includeClauseCuts: false,
    );
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

    final reportOnlyTypes = _reportOnlyTypes(
      candidates,
      statuses,
      reported,
      safety,
    );

    // Remove a dead member's overrides with it. If an override has to stay,
    // for example because it is in a doc-only type, keep the member too.
    final overridden = await _coupleOverrides(
      candidates,
      reported,
      overrides,
      kept: DeadSpans.of([
        for (final type in docOnlyTypes) _verdict.finding(type, rootPath),
      ], rootPath),
      rootPath: rootPath,
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
        // members: [_reportTypesWhole] reports the type.
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
    final cut = await _withCuts(client, unused, rootPath);
    final cutCandidateOf = {
      for (final (k, finding) in cut.indexed) finding: candidateOf[unused[k]]!,
    };
    // Members of a type reported once as report-only aren't reported, so
    // `--remove` must not count them as removed.
    final removable = _removableIndices(cutCandidateOf)
      ..removeWhere(
        (i) => reportOnlyTypes.containsKey(candidates[i].containerKey),
      );
    _removableBefore.addAll(removable);
    for (final (i, finding) in await _namedOnlyInClauses(
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
    _reportTypesWhole(
      cut,
      candidates,
      cutCandidateOf,
      reportOnlyTypes,
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

  /// Reports a type once, instead of a finding for each of its members.
  ///
  /// - A type in [reportOnlyTypes] gets one report-only finding with its hint.
  ///   Its members are not reported, so `--remove` keeps them all.
  /// - A type that is itself a removable finding, because it is unused or used
  ///   only in `with` and `implements` clauses, also removes what its members'
  ///   findings removed, like their overrides. Its members are not reported.
  ///
  /// Members of other types are still reported, and so is a member an earlier
  /// round found removable (see [_removableBefore]).
  void _reportTypesWhole(
    List<UnusedDeclaration> unused,
    List<Candidate> candidates,
    Map<UnusedDeclaration, int> candidateOf,
    Map<DeclKey, ({int type, String hint})> reportOnlyTypes,
    String rootPath,
  ) {
    Candidate candidateFor(UnusedDeclaration finding) =>
        candidates[candidateOf[finding]!];
    final deadTypes = {
      for (final finding in unused)
        if (candidateFor(finding) case final candidate
            when !finding.removalBlocked && candidate.container == null)
          candidate.key,
    };
    bool goesWithType(UnusedDeclaration finding) {
      final key = candidateFor(finding).containerKey;
      return deadTypes.contains(key) ||
          (reportOnlyTypes.containsKey(key) &&
              !_removableBefore.contains(candidateOf[finding]));
    }

    final removalsOf = unused
        .where(
          (finding) =>
              goesWithType(finding) &&
              deadTypes.contains(candidateFor(finding).containerKey) &&
              !finding.removalBlocked,
        )
        .groupFoldBy<DeclKey?, List<CoupledRemoval>>(
          (member) => candidateFor(member).containerKey,
          (removals, member) =>
              (removals ?? [])..addAll(member.coupledRemovals),
        );
    unused.removeWhere(goesWithType);
    for (final (j, finding) in unused.indexed.toList()) {
      final candidate = candidateFor(finding);
      if (candidate.container != null) {
        continue;
      }
      if (removalsOf[candidate.key] case final removals?
          when removals.isNotEmpty) {
        final folded = finding.copyWith(
          coupledRemovals: {...finding.coupledRemovals, ...removals}.toList(),
        );
        unused[j] = folded;
        candidateOf[folded] = candidateOf[finding]!;
      }
    }
    for (final (:type, :hint) in reportOnlyTypes.values) {
      final finding = _verdict.finding(
        candidates[type],
        rootPath,
        removalBlocked: true,
        hint: hint,
      );
      unused.add(finding);
      candidateOf[finding] = type;
    }
  }

  /// Returns a finding, with its candidate index, for each used class or mixin
  /// that only `with` and `implements` clauses in scanned files name and whose
  /// members are all in [removable], like `mixin M { void m() {} }` named only
  /// in `class A with M {}`.
  ///
  /// Each finding also removes the type from those clauses. A generic type, or
  /// one with a clause entry that can't be removed, gets no finding. Selection
  /// ranges are fetched only for the clauses of these types.
  Future<List<(int, UnusedDeclaration)>> _namedOnlyInClauses(
    LspClient client,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    List<List<Location>> liveRefs,
    Set<int> removable,
    DeadSpans deadSpans,
    Set<String> scannedPaths,
    String rootPath,
  ) async {
    final members = _removableMembers(candidates, removable);
    final entriesOf = <int, List<ClauseEntry>>{};
    for (final (i, candidate) in candidates.indexed) {
      final outline = candidate.outline.element;
      if (statuses[i] != .used ||
          !const <OutlineKind>{.class$, .mixin}.contains(outline.kind) ||
          (outline.typeParameters?.isNotEmpty ?? false) ||
          (candidate.symbol.children?.length ?? 0) !=
              (members[candidate.key]?.removable ?? 0)) {
        continue;
      }
      final refs = _classifier.externalRefs(candidate, liveRefs[i]);
      // The outline of every scanned file is already cached: the candidates
      // were read from it.
      final entries = [
        for (final loc in refs)
          if (scannedPaths.contains(SourceIndex.pathOf(loc.uri)))
            ?client
                .cachedOutline(Uri.parse(loc.uri))
                ?.let(
                  (unit) =>
                      _sources.clauseEntryAt(loc, candidate.symbol.name, unit),
                ),
      ];
      if (entries.length == refs.length) {
        entriesOf[i] = entries;
      }
    }
    await _fetch.fetchSelectionRanges(
      client,
      entriesOf.values.flattened.groupFoldBy(
        (entry) => entry.path,
        (names, entry) =>
            (names ?? <Position>{})
              ..addAll(_sources.namesInClause(entry.path, entry.clause)),
      ),
    );
    // Drop a type if any of its clause entries gets no removal: the clause's
    // selection ranges aren't cached, or the entry would take every mixin of
    // a mixin application class. Dropping a type keeps its entries, which changes the
    // removals of other entries in the same clause, so repeat until each type
    // left has all its removals.
    var cuts = _sources.clauseCuts(entriesOf.values.flattened, rootPath);
    bool lacksCut(List<ClauseEntry> entries) =>
        entries.any((e) => !cuts.containsKey(e));
    while (entriesOf.values.any(lacksCut)) {
      entriesOf.removeWhere((_, entries) => lacksCut(entries));
      cuts = _sources.clauseCuts(entriesOf.values.flattened, rootPath);
    }
    return [
      for (final MapEntry(key: i, value: entries) in entriesOf.entries)
        (
          i,
          _verdict.finding(
            candidates[i],
            rootPath,
            coupledRemovals: {
              for (final entry in entries) cuts[entry]!,
            }.toList(),
            hint: Verdict.namedOnlyInClausesHint,
            onlyReferencedFrom: _onlyReferencedFrom(
              candidates[i],
              refsByCandidate[i],
              deadSpans,
            ),
          ),
        ),
    ];
  }

  /// Returns the types reported once, as report-only, instead of their members,
  /// by key, with their candidate index and hint (see [_reportTypesWhole]):
  ///
  /// - a type that only doc comments mention, with a member in [reported];
  /// - a used enum whose values are all unused, like `enum E { a, b }` with
  ///   only `E` named, since removing the values would leave `enum E {}`.
  ///
  /// A member that an earlier round found removable doesn't count (see
  /// [_removableBefore]).
  Map<DeclKey, ({int type, String hint})> _reportOnlyTypes(
    List<Candidate> candidates,
    List<RefStatus> statuses,
    Set<int> reported,
    RemoveSafety safety,
  ) {
    final types = {
      for (final (i, candidate) in candidates.indexed)
        if (candidate.isType)
          if (switch ((statuses[i], candidate.symbol.kind)) {
                (.docOnly, _) => Verdict.docOnlyTypeHint,
                (.used, .enum$)
                    when safety.emptiedEnums.contains(candidate.key) =>
                  Verdict.emptiedEnumHint,
                _ => null,
              }
              case final hint?)
            candidate.key: (type: i, hint: hint),
    };
    return {
      for (final key
          in reported
              .whereNot(_removableBefore.contains)
              .map((i) => candidates[i].containerKey))
        ?key: ?types[key],
    };
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
    OverrideRemovals overrides, {
    required DeadSpans kept,
    required String rootPath,
  }) async {
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
      var result = _overridesByMember[index]!;
      if (result.removals.any((removal) => _isIn(kept, removal, rootPath))) {
        result = OverrideRemovals.blocked;
      }
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

  /// Whether [spans] cover the start of [removal].
  static bool _isIn(DeadSpans spans, CoupledRemoval removal, String rootPath) =>
      spans.covers(
        absoluteUnder(removal.filePath, rootPath),
        .new(
          line: removal.range.startLine,
          character: removal.range.startColumn,
        ),
      );

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
