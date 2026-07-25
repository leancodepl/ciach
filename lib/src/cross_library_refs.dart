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
import 'package:ciach/src/lexing.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source_index.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

/// A textual usage site to confirm: the identifier's position in a file, plus
/// the name it spells.
typedef _Site = ({Uri uri, Position position, String name});

/// A declaration's identity as a position: its file path and the
/// zero-based line/character where its name starts. This is exactly what
/// `textDocument/definition` reports as the resolved location, so it is the key
/// that matches a recovered usage back to a candidate declaration.
typedef _DeclPosition = (String path, int line, int character);

/// Recovers references the Dart analysis server's `textDocument/references`
/// does not report across library boundaries.
///
/// The server's reverse reference index omits two reference *shapes* when the
/// use is in a different library from the declaration, so a declaration used
/// only through one of them reads as having zero references and is falsely
/// reported unused:
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
/// name match. A lexer scan locates candidate usage sites textually, then each
/// site is confirmed with `textDocument/definition` and kept only if it
/// resolves back to a declaration under analysis. A site that resolves
/// elsewhere (a named argument, a map key, an unrelated member) simply never
/// matches a candidate, so the recovery is precise rather than heuristic: it
/// can only ever keep a declaration alive that the analyzer agrees is used.
class CrossLibraryReferences {
  const CrossLibraryReferences._(this._recovered);

  /// The declaration positions confirmed to be referenced via a recovered
  /// shape. A candidate whose name position is in here was a false positive.
  final Set<_DeclPosition> _recovered;

  /// An empty recovery: nothing to add back.
  static const empty = CrossLibraryReferences._(<_DeclPosition>{});

  /// Words after which a leading-dot `.name` is an expression (a dot-shorthand)
  /// rather than a member access on a receiver.
  static const _shorthandKeywords = {'return', 'yield', 'await', 'case'};

  /// Builds the recovery for the declarations whose reference query came back
  /// empty (their simple names are [emptyRefNames]).
  ///
  /// Scans every file [sources] has loaded for object-pattern-field and
  /// dot-shorthand sites that spell one of those names, confirms each with
  /// [LspClient.definition] (pooled at [concurrency]), and records every
  /// declaration a site resolves to. Only empty-ref names are probed, so a
  /// package with no false-positive candidates issues no extra requests.
  static Future<CrossLibraryReferences> resolve({
    required LspClient client,
    required SourceIndex sources,
    required Set<String> emptyRefNames,
    required int concurrency,
  }) async {
    if (emptyRefNames.isEmpty) {
      return empty;
    }
    final sites = <_Site>[];
    for (final path in sources.scannedPaths) {
      _collectSites(sources, path, emptyRefNames, sites);
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
  /// used through a recovered object-pattern or dot-shorthand site.
  bool isRecovered(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return _recovered.contains((candidate.path, start.line, start.character));
  }

  /// Appends every recoverable usage site in [path] that spells a name in
  /// [names] to [out].
  static void _collectSites(
    SourceIndex sources,
    String path,
    Set<String> names,
    List<_Site> out,
  ) {
    final tokens = sources.tokens(path);
    final uri = File(path).uri;
    for (var i = 0; i < tokens.length; i++) {
      final token = tokens[i];

      // Dot-shorthand: a leading-dot `.name` in an expression position. The
      // context filter only bounds how many sites are probed; a member access
      // that slips through resolves to its own receiver's member, never a
      // candidate, so it is discarded by the definition confirmation.
      if (!token.isWord &&
          token.value == '.' &&
          i + 1 < tokens.length &&
          tokens[i + 1].isWord &&
          names.contains(tokens[i + 1].value) &&
          _isDotShorthandContext(tokens, i)) {
        out.add(_siteAt(sources, path, uri, tokens[i + 1]));
        continue;
      }

      // Object-pattern field `Type(name: …)` / `Type(…, name: …)` — the field
      // name directly follows the `(` or a `,`. This also matches a named
      // argument of the same shape; the definition confirmation resolves that
      // to a parameter, not a candidate, and drops it.
      if (token.isWord &&
          names.contains(token.value) &&
          _followedByColon(tokens, i) &&
          _afterOpenParenOrComma(tokens, i)) {
        out.add(_siteAt(sources, path, uri, token));
        continue;
      }

      // Object-pattern shorthand `Type(:name)` / `Type(…, :name)` — a `:`
      // right after `(`/`,`, immediately followed by the bound getter name.
      if (!token.isWord &&
          token.value == ':' &&
          _afterOpenParenOrComma(tokens, i) &&
          i + 1 < tokens.length &&
          tokens[i + 1].isWord &&
          names.contains(tokens[i + 1].value)) {
        out.add(_siteAt(sources, path, uri, tokens[i + 1]));
      }
    }
  }

  static _Site _siteAt(
    SourceIndex sources,
    String path,
    Uri uri,
    Token token,
  ) => (
    uri: uri,
    position: sources.positionAt(path, token.start),
    name: token.value,
  );

  static bool _followedByColon(List<Token> tokens, int i) =>
      i + 1 < tokens.length &&
      !tokens[i + 1].isWord &&
      tokens[i + 1].value == ':';

  static bool _afterOpenParenOrComma(List<Token> tokens, int i) =>
      i > 0 &&
      !tokens[i - 1].isWord &&
      (tokens[i - 1].value == '(' || tokens[i - 1].value == ',');

  /// Whether the `.` at [i] begins a dot-shorthand: the preceding token puts it
  /// in an expression position, not after a receiver (which would make it a
  /// member access like `foo.bar` or a cascade `..bar`).
  static bool _isDotShorthandContext(List<Token> tokens, int i) {
    if (i == 0) {
      return false;
    }
    final prev = tokens[i - 1];
    if (prev.isWord) {
      return _shorthandKeywords.contains(prev.value);
    }
    switch (prev.value) {
      case '(' || ',' || '[' || '{' || '=' || ':':
        return true;
      case '>':
        // The `>` of an arrow `=>` body, not the `>` that closes a type
        // argument list (as in `List<int>.filled`).
        return i >= 2 && !tokens[i - 2].isWord && tokens[i - 2].value == '=';
      default:
        return false;
    }
  }
}
