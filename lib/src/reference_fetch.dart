import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/problems.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

final _log = Logger('ciach.finder');

const _uncheckedDeclaration = 'Could not find references; kept.';

const _noSemanticTokens =
    'Could not read comments and annotations; findings may be missed.';

const _noSelectionRanges =
    'Could not read the syntax here; review findings before removing.';

/// Requests what the verdict needs from the analysis server: each candidate's
/// references, plus the semantic tokens and selection ranges the structural
/// checks read, which it caches in the [SourceIndex].
final class ReferenceFetch {
  ReferenceFetch({required this.options, required SourceIndex sources})
    : _sources = sources;

  final FinderOptions options;
  final SourceIndex _sources;

  /// Queries `textDocument/references` for every candidate through one global
  /// pool, reporting `[done/total]` progress as each file's last query lands.
  /// A candidate whose request failed is left out, so it is never reported.
  Future<({List<Candidate> checked, List<List<Location>> refs})> references(
    LspClient client,
    List<Candidate> candidates, {
    required int totalFiles,
    required String rootPath,
  }) async {
    final remainingPerFile = <String, int>{};
    for (final candidate in candidates) {
      remainingPerFile.update(candidate.path, (n) => n + 1, ifAbsent: () => 1);
    }
    var filesDone = totalFiles - remainingPerFile.length;

    final fetched = await mapPooled(candidates, options.concurrency, (
      candidate,
    ) async {
      // The server would answer for an unnamed extension's `on` type.
      final refs = candidate.isUnnamedExtension
          ? const <Location>[]
          : await _referencesOf(client, candidate);
      if (remainingPerFile.update(candidate.path, (n) => n - 1) == 0) {
        filesDone++;
        _log.info(
          '[$filesDone/$totalFiles] '
          '${p.relative(candidate.path, from: rootPath)}',
        );
      }
      return refs;
    });

    final checked = <Candidate>[];
    final refs = <List<Location>>[];
    for (final (i, candidateRefs) in fetched.indexed) {
      if (candidateRefs != null) {
        checked.add(candidates[i]);
        refs.add(candidateRefs);
      }
    }
    return (checked: checked, refs: refs);
  }

  Future<List<Location>?> _referencesOf(
    LspClient client,
    Candidate candidate,
  ) async {
    final start = candidate.symbol.selectionRange.start;
    try {
      return await client.references(candidate.uri, start);
    } on LspRequestException catch (e) {
      final name = candidate.symbol.declarationName(candidate.container);
      recordProblem(
        _uncheckedDeclaration,
        e,
        path: candidate.path,
        position: start,
        name: candidate.container == null
            ? name
            : '${candidate.container}.$name',
      );
      return null;
    }
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
    await mapPooled(paths.toList(), options.concurrency, (path) async {
      _sources.cacheSemanticTokens(
        path,
        await semanticTokensOrEmpty(client, _sources, path),
      );
    });
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
    if (positionsByPath.isEmpty) {
      return;
    }
    _log.info(
      'Fetching syntax nodes in ${plural(positionsByPath.length, 'file', 'files')}…',
    );
    await mapPooled(positionsByPath.entries.toList(), options.concurrency, (
      entry,
    ) async {
      final MapEntry(key: path, value: positions) = entry;
      await _fetchSelectionRanges(client, path, positions.toList());
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

/// The semantic tokens of [path], or an empty list if the server has none.
/// A file without tokens reads as all code, which only keeps declarations.
Future<List<SemanticToken>> semanticTokensOrEmpty(
  LspClient client,
  SourceIndex sources,
  String path,
) async {
  try {
    return await client.semanticTokens(File(path).uri, sources.lines(path));
  } on LspRequestException catch (e) {
    recordProblem(_noSemanticTokens, e, path: path);
    return const [];
  }
}
