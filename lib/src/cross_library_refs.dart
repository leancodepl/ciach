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

/// Recovers references the analysis server's `textDocument/references` does not
/// report across library boundaries — object-pattern fields (`Type(field: …)`)
/// and dot-shorthands (`.member`) — which otherwise read as zero references and
/// are falsely reported unused. Candidate usage sites are found from the
/// server's semantic tokens and confirmed with `textDocument/definition`, whose
/// forward resolution does see them; a site is kept only if it resolves back to
/// a declaration under analysis, so live code is never dropped.
class CrossLibraryReferences {
  const CrossLibraryReferences._(this._recovered);

  final Set<_DeclPosition> _recovered;

  static const empty = CrossLibraryReferences._(<_DeclPosition>{});

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
    final sites = <_Site>[];
    for (final path in sources.scannedPaths) {
      final data = await client.semanticTokensFull(File(path).uri);
      _collectSites(
        sources: sources,
        path: path,
        data: data,
        tokenTypes: tokenTypes,
        names: emptyRefNames,
        declarations: declarations,
        out: sites,
      );
    }
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

    final recovered = <_DeclPosition>{};
    for (final locations in perSite) {
      for (final loc in locations) {
        final start = loc.range.start;
        recovered.add((
          SourceIndex.pathOf(loc.uri),
          start.line,
          start.character,
        ));
      }
    }
    return CrossLibraryReferences._(recovered);
  }

  bool isRecovered(Candidate candidate) =>
      _recovered.contains(_positionOf(candidate));

  static _DeclPosition _positionOf(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return (candidate.path, start.line, start.character);
  }

  static void _collectSites({
    required SourceIndex sources,
    required String path,
    required List<int> data,
    required List<String> tokenTypes,
    required Set<String> names,
    required Set<_DeclPosition> declarations,
    required List<_Site> out,
  }) {
    final lines = sources.lines(path);
    final uri = File(path).uri;
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
      out.add((uri: uri, position: Position(line: line, character: char)));
    }
  }

  static String? _slice(String lineText, int char, int length) {
    if (char < 0 || char + length > lineText.length) {
      return null;
    }
    return lineText.substring(char, char + length);
  }
}
