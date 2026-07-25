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

/// A usage site to confirm: the identifier's position in a file.
typedef _Site = ({Uri uri, Position position});

/// A declaration's identity as a position: its file path and the zero-based
/// line/character where its name starts. This is exactly what
/// `textDocument/definition` reports as the resolved location, so it is the key
/// that matches a recovered usage back to a candidate declaration.
typedef _DeclPosition = (String path, int line, int character);

/// Recovers references the Dart analysis server's `textDocument/references`
/// does not report across library boundaries.
///
/// The server's reverse reference index omits some reference *shapes* when the
/// use is in a different library from the declaration, so a declaration used
/// only through one of them reads as having zero references and is falsely
/// reported unused. Two confirmed cases:
///
///  * **Object-pattern fields** — `Type(field: subpattern)` and the `:field`
///    shorthand. The instance getter/field named by the pattern field is
///    resolved by the analyzer but not indexed as a reference
///    (leancodepl/ciach#24).
///  * **Dot-shorthands** — a leading-dot `.member` access (Dart 3.10) that
///    resolves against a context type without importing the declaring library,
///    so an enum value, static member or named constructor used only through
///    one reads as unused (leancodepl/ciach#25).
///
/// For both shapes the analyzer's *forward* resolution still works — that is
/// why `dart analyze` sees the use — so this recovers them without a fragile
/// name match. Candidate usage sites are found from the analysis server's own
/// **semantic tokens** (every member/type reference is tagged with its name
/// position and a token type), and each one is confirmed with
/// `textDocument/definition`, kept only if it resolves back to a declaration
/// under analysis. A site that resolves elsewhere (a named argument, a same-
/// named local, an unrelated member) simply never matches a candidate, so the
/// recovery is precise rather than heuristic: it can only ever keep a
/// declaration alive that the analyzer agrees is used.
class CrossLibraryReferences {
  const CrossLibraryReferences._(this._recovered);

  /// The declaration positions confirmed to be referenced via a recovered
  /// shape. A candidate whose name position is in here was a false positive.
  final Set<_DeclPosition> _recovered;

  /// An empty recovery: nothing to add back.
  static const empty = CrossLibraryReferences._(<_DeclPosition>{});

  /// Semantic-token type names that denote a reference to a member or type
  /// declaration — as opposed to a keyword, literal, comment, parameter or
  /// local. Deliberately over-inclusive: correctness comes from the
  /// `definition` confirmation, so this only needs to bound which sites are
  /// probed, not to precisely classify them.
  static const _memberTokenTypes = {
    'class',
    'method',
    'enum',
    'enumMember',
    'property',
    'function',
    'type',
  };

  /// Builds the recovery for the [candidates] whose reference query came back
  /// empty (their simple names are [emptyRefNames]).
  ///
  /// Requests semantic tokens for every file [sources] has loaded, keeps the
  /// tokens that name one of those declarations (skipping the declarations
  /// themselves and dartdoc mentions), confirms each with
  /// [LspClient.definition] (pooled at [concurrency]), and records every
  /// declaration a site resolves to. Only empty-ref names are probed, so a
  /// package with no false-positive candidates issues no extra requests.
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
      // The server advertised no semantic-tokens legend; nothing to recover.
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
        // A position the server can't resolve is simply not a recovered use.
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

  /// Whether [candidate] — already found to have no references — is in fact
  /// used through a recovered site.
  bool isRecovered(Candidate candidate) =>
      _recovered.contains(_positionOf(candidate));

  static _DeclPosition _positionOf(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return (candidate.path, start.line, start.character);
  }

  /// Decodes the delta-encoded semantic-token [data] for [path] and appends the
  /// member-reference tokens that spell a name in [names] to [out], skipping
  /// declaration sites (which resolve to themselves) and dartdoc mentions.
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
    // Each token is five ints: deltaLine, deltaStartChar, length, tokenType,
    // tokenModifiers. deltaStartChar is relative to the previous token's start
    // only when on the same line, otherwise to the line start.
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
      // A declaration's own name token resolves to itself; never treat it as a
      // use, or every unreferenced member would recover itself.
      if (declarations.contains((path, line, char))) {
        continue;
      }
      // A dartdoc `[Name]` mention is a doc-only reference, handled by the
      // classifier; it must not count as a real use here.
      if (lines[line].trimLeft().startsWith('///')) {
        continue;
      }
      out.add((uri: uri, position: Position(line: line, character: char)));
    }
  }

  /// The `[char, char + length)` slice of [lineText], or `null` if it runs past
  /// the line (a multi-line or malformed token).
  static String? _slice(String lineText, int char, int length) {
    if (char < 0 || char + length > lineText.length) {
      return null;
    }
    return lineText.substring(char, char + length);
  }
}
