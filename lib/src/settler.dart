import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/dead_spans.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/overrides.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/superclasses.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/verdict.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// What a run reports, sorted by location.
typedef Settled = ({
  List<UnusedDeclaration> unused,
  List<UnusedDeclaration> docOnly,
  List<RecoveredReference> recovered,
});

/// From references to findings. Classifies every candidate and, with
/// `transitive`, settles: each round drops the references inside the previous
/// round's removable findings and classifies again, until a round adds
/// nothing. No new reference queries; the cross-library probe covers only the
/// names a round newly emptied, and override and superclass lookups are
/// remembered across rounds.
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

  /// Already probed by the cross-library recovery.
  final _probedNames = <String>{};

  /// Override verdicts by candidate index; they don't depend on the round.
  final _overridesByMember = <int, OverriddenMember>{};

  /// A guard: the deleted text only grows between rounds, so it settles.
  static const _maxRounds = 16;

  void _report(String message) => options.onProgress?.call(message);

  /// The findings for [candidates], from the server's [refsByCandidate].
  /// Round one, with nothing dropped, is the plain result.
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

    var deadSpans = DeadSpans.empty;
    var crossLib = CrossLibraryReferences.empty;
    Settled settled;
    for (var round = 1; ; round++) {
      final liveRefs = _liveRefs(refsByCandidate, deadSpans);
      crossLib = crossLib.merged(
        await _recoverCrossLibraryRefs(client, candidates, liveRefs),
      );
      settled = await _round(
        candidates,
        refsByCandidate,
        liveRefs,
        crossLib.where((path, position) => !deadSpans.covers(path, position)),
        deadSpans,
        superclasses,
        overrides,
        rootPath,
        analysisRoot,
      );
      if (!options.transitive) {
        break;
      }
      final next = DeadSpans.of(settled.unused, rootPath);
      if (next.sameAs(deadSpans)) {
        if (round > 1) {
          _report('Settled after $round round(s).');
        }
        break;
      }
      if (round == _maxRounds) {
        _report(
          'Stopping after $_maxRounds rounds with findings still being '
          'added; the report is what the last round found.',
        );
        break;
      }
      _report(
        'Round ${round + 1}: ${next.length - deadSpans.length} more '
        'declaration(s) removable, checking what only they referenced…',
      );
      deadSpans = next;
    }
    return (
      unused: settled.unused.sorted(compareByLocation),
      docOnly: settled.docOnly.sorted(compareByLocation),
      recovered: settled.recovered,
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

  /// One round, from [liveRefs]; [refsByCandidate] is the server's full
  /// answer, for [_onlyReferencedFrom].
  Future<Settled> _round(
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

    // Names of classes flagged unused, per file. A whole dead class is
    // removed as one node, taking its own constructor(s) with it, so those
    // constructors must not also be reported (or removed) on their own.
    final deadClassNames = <String, Set<String>>{};
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (statuses[i] == .unused && candidate.symbol.kind == .class$) {
        deadClassNames
            .putIfAbsent(candidate.path, () => <String>{})
            .add(candidate.symbol.name);
      }
    }

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
    final docOnly = <UnusedDeclaration>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final refs = liveRefs[i];
      switch (statuses[i]) {
        case .unused:
          if (!reported.contains(i)) {
            break;
          }
          final isClass = candidate.symbol.kind == .class$;
          final overrides = overridden[i];
          final blockedByOverride = overrides?.blocked ?? false;
          unused.add(
            _verdict.finding(
              candidate,
              rootPath,
              coupledRemovals: isClass
                  ? _sources.pairedStateRemovals(
                      candidate,
                      refs,
                      candidates,
                      liveRefs,
                      rootPath,
                    )
                  : overrides?.removals ?? const [],
              removalBlocked:
                  _verdict.isRemovalBlocked(candidate, refs, safety) ||
                  blockedByOverride,
              hint:
                  _verdict.hintFor(candidate) ??
                  (blockedByOverride ? Verdict.overriddenHint : null),
              onlyReferencedFrom: _onlyReferencedFrom(
                candidate,
                refsByCandidate[i],
                deadSpans,
              ),
            ),
          );
        case .docOnly:
          docOnly.add(_verdict.finding(candidate, rootPath));
        case .used:
          break;
      }
    }

    // A finding dead only because its container is goes with the container.
    if (deadSpans.isNotEmpty) {
      final removable = DeadSpans.of(unused, rootPath);
      unused.removeWhere(
        (finding) =>
            finding.onlyReferencedFrom.isNotEmpty &&
            removable.enclosesInAnother(finding, rootPath),
      );
    }

    return (unused: unused, docOnly: docOnly, recovered: recovered);
  }

  /// Every finding whose removal deletes a reference to [candidate], in
  /// source order, as `qualifiedName (file:line)`. The references come in the
  /// server's order, so they are sorted; several dead declarations may have
  /// referenced the same one.
  List<String> _onlyReferencedFrom(
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
        '${owner.qualifiedName} (${owner.filePath}:${owner.line})',
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
    if (unchecked.isNotEmpty) {
      _report('Checking ${unchecked.length} dead member(s) for overrides…');
      final results = await mapPooled(
        unchecked,
        options.concurrency,
        (index) => overrides.of(candidates[index]),
      );
      for (var i = 0; i < unchecked.length; i++) {
        _overridesByMember[unchecked[i]] = results[i];
      }
    }
    final byCandidate = <int, OverriddenMember>{};
    var coupled = 0;
    var blocked = 0;
    for (final index in members) {
      final result = _overridesByMember[index]!;
      if (result.removals.isEmpty && !result.blocked) {
        continue;
      }
      byCandidate[index] = result;
      coupled += result.removals.length;
      if (result.blocked) {
        blocked++;
      }
    }
    if (coupled > 0) {
      _report(
        'Coupling $coupled override(s) to the dead member(s) they implement.',
      );
    }
    if (blocked > 0) {
      _report(
        '$blocked dead member(s) are overridden where --remove cannot '
        'follow; left in place.',
      );
    }
    return byCandidate;
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
  /// outside their own span — the potential false positives. A name probed in
  /// an earlier round is not probed again; the caller filters the sites.
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
      return Future.value(CrossLibraryReferences.empty);
    }
    _probedNames.addAll(emptyRefNames);
    _report('Recovering cross-library references…');
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
