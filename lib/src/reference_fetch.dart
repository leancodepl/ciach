import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, SelectionRange;

/// The server round trips the verdict runs on: every candidate's references,
/// and the tokens and syntax nodes the structural checks read, cached in the
/// [SourceIndex].
final class ReferenceFetch {
  ReferenceFetch({required this.options, required SourceIndex sources})
    : _sources = sources;

  final FinderOptions options;
  final SourceIndex _sources;

  void _report(String message) => options.onProgress?.call(message);

  /// Queries `textDocument/references` for every candidate through one global
  /// pool, reporting `[done/total]` progress as each file's last query lands.
  Future<List<List<Location>>> references(
    LspClient client,
    List<Candidate> candidates, {
    required int totalFiles,
    required String rootPath,
  }) {
    final remainingPerFile = <String, int>{};
    for (final candidate in candidates) {
      remainingPerFile.update(candidate.path, (n) => n + 1, ifAbsent: () => 1);
    }
    var filesDone = totalFiles - remainingPerFile.length;

    return mapPooled(candidates, options.concurrency, (candidate) async {
      // The server would answer for an unnamed extension's `on` type.
      final refs = candidate.isUnnamedExtension
          ? const <Location>[]
          : await client.references(
              candidate.uri,
              candidate.symbol.selectionRange.start,
            );
      if (remainingPerFile.update(candidate.path, (n) => n - 1) == 0) {
        filesDone++;
        _report(
          '[$filesDone/$totalFiles] '
          '${p.relative(candidate.path, from: rootPath)}',
        );
      }
      return refs;
    });
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
    _report('Fetching tokens for ${paths.length} referenced file(s)…');
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
    void add(String path, Position position) =>
        positionsByPath.putIfAbsent(path, () => {}).add(position);

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final kind = candidate.symbol.kind;
      final isEnumType = kind == .enum$ && !candidate.isEnumValue;
      if (isEnumType || kind == .class$) {
        for (final loc in refsByCandidate[i]) {
          add(SourceIndex.pathOf(loc.uri), loc.range.start);
        }
      }
      if ((kind == .constructor || kind == .field) &&
          candidate.containerOutline != null) {
        add(candidate.path, candidate.symbol.selectionRange.start);
      }
      if (isEnumType) {
        for (final token in _sources.valuesTokensIn(candidate)) {
          add(candidate.path, token.start);
        }
      }
      if (kind == .constructor) {
        if (_sources.redirectProbePosition(candidate) case final position?) {
          add(candidate.path, position);
        }
      }
    }
    if (positionsByPath.isEmpty) {
      return;
    }
    _report('Fetching syntax nodes in ${positionsByPath.length} file(s)…');
    await mapPooled(positionsByPath.entries.toList(), options.concurrency, (
      entry,
    ) async {
      final MapEntry(key: path, value: positions) = entry;
      final ordered = positions.toList();
      List<SelectionRange?> ranges;
      try {
        ranges = await client.selectionRanges(File(path).uri, ordered);
      } on Object {
        return; // a position with no answer reads as "not the special shape"
      }
      for (var i = 0; i < ordered.length; i++) {
        if (ranges[i] case final range?) {
          _sources.cacheSelectionRange(path, ordered[i], range);
        }
      }
    });
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
  } on Object {
    return const [];
  }
}
