/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source_index.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

typedef _Site = ({Uri uri, Position position});

typedef _DeclPosition = (String path, int line, int character);

/// A secondary check for declarations that appear to have zero references.
/// Before one is reported unused, a `textDocument/definition` lookup confirms
/// whether any use actually resolves back to it; candidate use-sites come from
/// semantic tokens, and a site counts only when definition resolves it to a
/// declaration under analysis, so correctness comes from that confirmation
/// (candidate-finding only needs to be over-inclusive) and live code is never
/// dropped. It self-deactivates: when references are already complete, a
/// zero-reference declaration is genuinely dead, nothing resolves to it, and
/// this is a no-op.
class CrossLibraryReferences {
  const CrossLibraryReferences._(this._usageByDecl);

  /// Recovered declaration position -> the usage site that confirmed it.
  final Map<_DeclPosition, _Site> _usageByDecl;

  static const empty = CrossLibraryReferences._(<_DeclPosition, _Site>{});

  /// Over-inclusive on purpose: the `definition` confirmation, not this set, is
  /// what makes the recovery correct.
  static const _memberTokenTypes = {
    'class',
    'method',
    'enum',
    'enumMember',
    'property',
    'function',
    'type',
  };

  /// Only the [emptyRefNames] (simple names of the zero-reference [candidates])
  /// are probed, so a package with no false positives issues no extra requests.
  static Future<CrossLibraryReferences> resolve({
    required LspClient client,
    required SourceIndex sources,
    required List<Candidate> candidates,
    required Set<String> emptyRefNames,
    required int concurrency,
  }) async {
    if (emptyRefNames.isEmpty) {
      return empty;
    }
    final tokenTypes = client.semanticTokenTypes;
    if (tokenTypes.isEmpty) {
      return empty;
    }

    final declarations = <_DeclPosition>{
      for (final candidate in candidates) _positionOf(candidate),
    };

    // A matched slice is always a substring of the file, so a file mentioning
    // none of the names cannot contribute a site — skip its request entirely.
    final paths = [
      for (final path in sources.scannedPaths)
        if (_mentionsAny(sources.content(path), emptyRefNames)) path,
    ];
    if (paths.isEmpty) {
      return empty;
    }

    final perFile = await mapPooled(paths, concurrency, (path) async {
      try {
        return await client.semanticTokensFull(File(path).uri);
      } on Object {
        return const <int>[];
      }
    });

    final sites = [
      for (var i = 0; i < paths.length; i++)
        ..._collectSites(
          sources: sources,
          path: paths[i],
          data: perFile[i],
          tokenTypes: tokenTypes,
          names: emptyRefNames,
          declarations: declarations,
        ),
    ];
    if (sites.isEmpty) {
      return empty;
    }

    final perSite = await mapPooled(sites, concurrency, (site) async {
      try {
        return await client.definition(site.uri, site.position);
      } on Object {
        return const <Location>[];
      }
    });

    final usageByDecl = <_DeclPosition, _Site>{};
    for (var i = 0; i < sites.length; i++) {
      for (final loc in perSite[i]) {
        final start = loc.range.start;
        final pos = (SourceIndex.pathOf(loc.uri), start.line, start.character);
        if (declarations.contains(pos)) {
          usageByDecl.putIfAbsent(pos, () => sites[i]);
        }
      }
    }
    return CrossLibraryReferences._(usageByDecl);
  }

  bool isRecovered(Candidate candidate) =>
      _usageByDecl.containsKey(_positionOf(candidate));

  /// The usage site that recovered [candidate], or `null` if not recovered.
  ({String path, int line, int character})? recoveredUsage(
    Candidate candidate,
  ) {
    final site = _usageByDecl[_positionOf(candidate)];
    if (site == null) {
      return null;
    }
    return (
      path: site.uri.toFilePath(),
      line: site.position.line,
      character: site.position.character,
    );
  }

  static _DeclPosition _positionOf(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return (candidate.path, start.line, start.character);
  }

  static bool _mentionsAny(String content, Set<String> names) =>
      names.any(content.contains);

  static List<_Site> _collectSites({
    required SourceIndex sources,
    required String path,
    required List<int> data,
    required List<String> tokenTypes,
    required Set<String> names,
    required Set<_DeclPosition> declarations,
  }) {
    final lines = sources.lines(path);
    final uri = File(path).uri;
    final sites = <_Site>[];
    var line = 0;
    var char = 0;
    // LSP semantic tokens: five ints each — deltaLine, deltaStartChar (relative
    // to the previous token only on the same line), length, tokenType, mods.
    for (var i = 0; i + 4 < data.length; i += 5) {
      final deltaLine = data[i];
      if (deltaLine > 0) {
        line += deltaLine;
        char = data[i + 1];
      } else {
        char += data[i + 1];
      }
      final length = data[i + 2];
      final typeIndex = data[i + 3];

      if (typeIndex < 0 || typeIndex >= tokenTypes.length) {
        continue;
      }
      if (!_memberTokenTypes.contains(tokenTypes[typeIndex])) {
        continue;
      }
      if (line < 0 || line >= lines.length) {
        continue;
      }
      final text = _slice(lines[line], char, length);
      if (text == null || !names.contains(text)) {
        continue;
      }
      // A declaration's own token resolves to itself, so skip it — otherwise
      // every unreferenced member would recover itself.
      if (declarations.contains((path, line, char))) {
        continue;
      }
      // A dartdoc mention is a doc-only reference, not a real use.
      if (lines[line].trimLeft().startsWith('///')) {
        continue;
      }
      sites.add((uri: uri, position: Position(line: line, character: char)));
    }
    return sites;
  }

  static String? _slice(String lineText, int char, int length) {
    if (char < 0 || char + length > lineText.length) {
      return null;
    }
    return lineText.substring(char, char + length);
  }
}
