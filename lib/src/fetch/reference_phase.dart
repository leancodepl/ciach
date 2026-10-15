/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/subtype_counts.dart';
import 'package:ciach/src/fetch/member_probe.dart';
import 'package:ciach/src/fetch/reachable_types.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:ciach/src/workspace/public_api.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.finder');

/// The references of the collected candidates, asked for in the order that
/// lets the cheaper lookups settle most of them.
///
/// A references search for a member builds the member's override hierarchy
/// on every request. For a member of a type with many subtypes, that takes
/// most of a second, often several, however few references it has. So
/// everything else goes first, including the types themselves. Then those
/// members go to a [MemberProbe], in the files that name their type, and
/// only those it finds no use of get a references search.
///
/// Members of an unexported type wait until the types' references show
/// which ones another package can reach, and are probed the same way.
/// Without an exported package, so are the members of a private type: a
/// references search for a name without an underscore covers the whole
/// workspace, but their uses are almost always in the files that name the
/// type. The settling completes the uses a probe found before calling a
/// member dead.
final class ReferencePhase {
  ReferencePhase({
    required this.options,
    required SourceIndex sources,
    required ReferenceFetch fetch,
    required PublicApi? publicApi,
    required SubtypeCounts subtypeCounts,
  }) : _sources = sources,
       _fetch = fetch,
       _publicApi = publicApi,
       _subtypeCounts = subtypeCounts;

  final FinderOptions options;
  final SourceIndex _sources;
  final ReferenceFetch _fetch;
  final PublicApi? _publicApi;
  final SubtypeCounts _subtypeCounts;

  /// A type with this many subtypes makes a references search for one of its
  /// members slow enough to try the cheaper lookups first.
  static const _manySubtypes = 10;

  /// The references of [collected], less the candidates left unchecked, and
  /// the probe that found some of them, whose references are only the uses
  /// it found.
  Future<
    ({
      List<Candidate> candidates,
      List<List<Location>> refsByCandidate,
      MemberProbe? probe,
    })
  >
  run(
    LspClient client,
    List<Candidate> collected, {
    required int totalFiles,
    required String rootPath,
  }) async {
    final api = _publicApi;
    final gated = collected
        .where(api == null ? _isPrivateTypeMember : ReachableTypes.isGated)
        .toSet();
    final inLargeHierarchy = {
      for (final candidate in collected)
        if (!gated.contains(candidate) && _isInLargeHierarchy(candidate))
          candidate,
    };
    final candidates = <Candidate>[];
    final refsByCandidate = <List<Location>>[];
    Future<void> fetch(List<Candidate> batch, int files) async {
      _log.info(
        'Checking references for ${plural(batch.length, 'declaration', 'declarations')}…',
      );
      final fetched = await _fetch.references(
        client,
        batch,
        totalFiles: files,
        rootPath: rootPath,
      );
      await _fetch.semanticTokensFor(client, fetched.refs);
      candidates.addAll(fetched.checked);
      refsByCandidate.addAll(fetched.refs);
    }

    await fetch(
      collected
          .whereNot(gated.contains)
          .whereNot(inLargeHierarchy.contains)
          .toList(),
      totalFiles,
    );
    if (gated.isEmpty && inLargeHierarchy.isEmpty) {
      return (
        candidates: candidates,
        refsByCandidate: refsByCandidate,
        probe: null,
      );
    }

    final filesNaming = _filesNamingTypes(candidates, refsByCandidate);
    Set<String> filesNamingType(Candidate member) =>
        filesNaming[member.containerKey] ?? {member.path};
    final List<Candidate> gatedMembers;
    var filesFor = filesNamingType;
    if (api == null) {
      gatedMembers = gated.toList();
    } else {
      final types = await ReachableTypes.find(
        client: client,
        sources: _sources,
        fetch: _fetch,
        api: api,
        candidates: candidates,
        refs: refsByCandidate,
      );
      gatedMembers = gated.where(types.isInternal).toList();
      final internal = gatedMembers.toSet();
      filesFor = (member) => internal.contains(member)
          ? types.filesFor(member)
          : filesNamingType(member);
    }
    final members = [...gatedMembers, ...inLargeHierarchy];
    _log.info(
      'Looking up uses of ${plural(members.length, 'member', 'members')} '
      'where their types are named…',
    );
    final probe = MemberProbe(
      client: client,
      sources: _sources,
      concurrency: options.concurrency,
    );
    final probed = await probe.probe(filesFor: filesFor, members: members);
    candidates.addAll(probed.used);
    refsByCandidate.addAll(probed.refs);
    await fetch(probed.rest, probed.rest.map((c) => c.path).toSet().length);
    return (
      candidates: candidates,
      refsByCandidate: refsByCandidate,
      probe: probe,
    );
  }

  /// Whether [candidate] is a member of a type with so many subtypes that a
  /// references search for it is slow. A constructor is no part of an
  /// override hierarchy.
  bool _isInLargeHierarchy(Candidate candidate) =>
      candidate.container != null &&
      candidate.containerOutline?.element.kind != .extension &&
      candidate.symbol.kind != .constructor &&
      _subtypeCounts.of(candidate.container!) >= _manySubtypes;

  /// Whether [candidate] is a member of a private type that its name alone
  /// doesn't make private.
  static bool _isPrivateTypeMember(Candidate candidate) =>
      ReachableTypes.isGated(candidate) && isPrivateName(candidate.container!);

  /// For each type among [candidates], its file and the files that name it,
  /// from its [refs].
  static Map<DeclKey, Set<String>> _filesNamingTypes(
    List<Candidate> candidates,
    List<List<Location>> refs,
  ) => {
    for (final (i, candidate) in candidates.indexed)
      if (candidate.isType)
        candidate.key: {
          candidate.path,
          for (final loc in refs[i]) SourceIndex.pathOf(loc.uri),
        },
  };
}
