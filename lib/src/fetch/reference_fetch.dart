import 'dart:io';

import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/source/syntax_rules.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';

final _log = Logger('ciach.finder');

const _uncheckedDeclaration = 'Could not find references; kept.';

const _noDeclaration =
    'The analyzer found no declaration whose name starts here.';

const _noSelectionRanges =
    'Could not read the syntax here; review findings before removing.';

/// Gets what the verdict needs: each candidate's references from the
/// analyzer, and from the analysis server the semantic tokens and selection
/// ranges that the structural checks read, which it caches in the
/// [SourceIndex].
final class ReferenceFetch {
  ReferenceFetch({required this.options, required SourceIndex sources})
    : _sources = sources;

  final FinderOptions options;
  final SourceIndex _sources;

  /// The references of each of [candidates], from [files] after they resolved
  /// every file under the analysis root. A candidate whose declaration the
  /// analyzer doesn't find is left out, so it is never reported.
  ({List<Candidate> checked, List<List<Location>> refs}) references(
    ResolvedFiles files,
    List<Candidate> candidates,
  ) {
    final found = [
      for (final candidate in candidates)
        if (_referencesOf(files, candidate) case final refs?)
          (candidate: candidate, refs: refs),
    ];
    return (
      checked: [for (final (:candidate, refs: _) in found) candidate],
      refs: [for (final (candidate: _, :refs) in found) refs],
    );
  }

  List<Location>? _referencesOf(ResolvedFiles files, Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    final refs = files.referencesTo(candidate.path, start);
    if (refs == null) {
      final name = candidate.symbol.declarationName(candidate.container);
      recordProblem(
        _uncheckedDeclaration,
        _noDeclaration,
        path: candidate.path,
        position: start,
        name:
            candidate.container?.let((container) => '$container.$name') ?? name,
      );
    }
    return refs;
  }

  /// Fetches the semantic tokens of every referenced file that has none yet.
  Future<void> semanticTokensFor(
    LspClient client,
    List<List<Location>> refsByCandidate,
  ) async {
    final paths = <String>{
      for (final refs in refsByCandidate)
        for (final loc in refs)
          if (!_sources.hasSemanticTokens(SourceIndex.pathOf(loc.uri)))
            SourceIndex.pathOf(loc.uri),
    };
    if (paths.isEmpty) {
      return;
    }
    _log.info(
      'Fetching tokens for ${plural(paths.length, 'referenced file', 'referenced files')}…',
    );
    await mapPooled(
      paths.toList(),
      options.concurrency,
      (path) => _sources.semanticTokensOf(client, path),
    );
  }

  /// Fetches the selection ranges the structural checks need, one request per
  /// file.
  Future<void> selectionRanges(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
  ) async {
    final positionsByPath = <String, Set<Position>>{};
    for (final (i, candidate) in candidates.indexed) {
      for (final (:path, :position) in _probes(candidate, refsByCandidate[i])) {
        positionsByPath.putIfAbsent(path, () => {}).add(position);
      }
    }
    await fetchSelectionRanges(client, positionsByPath);
  }

  /// Fetches and caches the selection ranges at [positionsByPath] not cached
  /// yet, one request per file.
  Future<void> fetchSelectionRanges(
    LspClient client,
    Map<String, Set<Position>> positionsByPath,
  ) async {
    final pending = {
      for (final MapEntry(key: path, value: positions)
          in positionsByPath.entries)
        if (positions
                .where((p) => _sources.selectionRangeAt(path, p) == null)
                .toList()
            case final missing when missing.isNotEmpty)
          path: missing,
    };
    if (pending.isEmpty) {
      return;
    }
    _log.info(
      'Fetching syntax nodes in ${plural(pending.length, 'file', 'files')}…',
    );
    await mapPooled(pending.entries.toList(), options.concurrency, (
      entry,
    ) async {
      final MapEntry(key: path, value: missing) = entry;
      await _fetchSelectionRanges(client, path, missing);
    });
  }

  /// The positions in which files whose syntax node the structural checks
  /// need for [candidate] and its [refs].
  Iterable<({String path, Position position})> _probes(
    Candidate candidate,
    List<Location> refs,
  ) sync* {
    final kind = candidate.symbol.kind;
    final isEnumType = kind == .enum$ && !candidate.isEnumValue;
    if (isEnumType || kind == .class$) {
      for (final loc in refs) {
        yield (path: SourceIndex.pathOf(loc.uri), position: loc.range.start);
      }
    }
    if ((kind == .constructor || kind == .field) &&
        candidate.containerOutline != null) {
      yield (
        path: candidate.path,
        position: candidate.symbol.selectionRange.start,
      );
    }
    if (isEnumType) {
      for (final token in _sources.valuesTokensIn(candidate)) {
        yield (path: candidate.path, position: token.start);
      }
    }
    if (kind == .constructor) {
      if (_sources.redirectProbePosition(candidate) case final position?) {
        yield (path: candidate.path, position: position);
      }
    }
  }

  Future<void> _fetchSelectionRanges(
    LspClient client,
    String path,
    List<Position> positions,
  ) async {
    try {
      final ranges = await client.selectionRanges(File(path).uri, positions);
      for (final (i, position) in positions.indexed) {
        if (ranges[i] case final range?) {
          _sources.cacheSelectionRange(path, position, range);
        }
      }
    } on LspRequestException catch (e) {
      // A position with no cached range reads as "not the special shape".
      recordProblem(
        _noSelectionRanges,
        e,
        path: path,
        position: positions.first,
      );
    }
  }
}
