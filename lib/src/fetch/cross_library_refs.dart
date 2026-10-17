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

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:collection/collection.dart';
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

  /// Recovered declaration position -> every usage site that confirmed it,
  /// so dropping a dead one never drops a live one.
  final Map<_DeclPosition, Set<_Site>> _usageByDecl;

  static const empty = CrossLibraryReferences._(<_DeclPosition, Set<_Site>>{});

  static const _unresolvedSite =
      'Could not resolve a possible use; check findings before removing.';

  /// Over-inclusive on purpose: the `definition` confirmation, not this set, is
  /// what makes the recovery correct.
  static const _memberTokenTypes = {
    'class',
    'method',
    'enum',
    'enumMember',
    'property',
    'variable',
    'function',
    'type',
  };

  /// Only the [emptyRefNames] (simple names of the zero-reference [candidates])
  /// are probed, so a package with no false positives issues no extra requests.
  /// The sites of the [reportedRefs] are not: the server already resolved
  /// them.
  static Future<CrossLibraryReferences> resolve({
    required LspClient client,
    required SourceIndex sources,
    required List<Candidate> candidates,
    required Set<String> emptyRefNames,
    required Iterable<Location> reportedRefs,
    required int concurrency,
  }) async {
    if (emptyRefNames.isEmpty) {
      return empty;
    }

    final byPosition = <_DeclPosition, Candidate>{
      for (final candidate in candidates) _positionOf(candidate): candidate,
    };
    final reported = reportedRefs.map(_positionOfLocation).toSet();

    final sites = [
      for (final path in sources.scannedPaths)
        ..._collectSites(
          sources: sources,
          path: path,
          names: emptyRefNames,
          skipped: (position) =>
              byPosition.containsKey(position) || reported.contains(position),
        ),
    ];
    if (sites.isEmpty) {
      return empty;
    }

    final perSite = await mapPooled(sites, concurrency, (site) async {
      try {
        return await client.definition(site.uri, site.position);
      } on LspRequestException catch (e) {
        recordProblem(
          _unresolvedSite,
          e,
          path: site.uri.toFilePath(),
          position: site.position,
        );
        return const <Location>[];
      }
    });

    final usageByDecl = <_DeclPosition, Set<_Site>>{};
    // Uses resolving to a non-candidate (e.g. an override), by name.
    final elsewhere = <String, Map<_DeclPosition, Set<_Site>>>{};
    for (final (i, (:uri, :position, :name)) in sites.indexed) {
      final site = (uri: uri, position: position);
      for (final loc in perSite[i]) {
        final pos = _positionOfLocation(loc);
        if (byPosition[pos] case final declaration?) {
          if (!_isSelfUse(site, declaration)) {
            usageByDecl.putIfAbsent(pos, () => {}).add(site);
          }
        } else if (pos != _positionOfSite(site)) {
          // Skip a declaration's own name.
          elsewhere
              .putIfAbsent(name, () => {})
              .putIfAbsent(pos, () => {})
              .add(site);
        }
      }
    }
    await _recoverThroughOverrides(
      client: client,
      candidates: candidates,
      elsewhere: elsewhere,
      usageByDecl: usageByDecl,
      concurrency: concurrency,
    );
    return ._(usageByDecl);
  }

  /// A use resolving to an override keeps the member it overrides alive.
  static Future<void> _recoverThroughOverrides({
    required LspClient client,
    required List<Candidate> candidates,
    required Map<String, Map<_DeclPosition, Set<_Site>>> elsewhere,
    required Map<_DeclPosition, Set<_Site>> usageByDecl,
    required int concurrency,
  }) async {
    final members = [
      for (final candidate in candidates)
        if (candidate.container != null &&
            elsewhere.containsKey(_simpleName(candidate.symbol.name)) &&
            !usageByDecl.containsKey(_positionOf(candidate)))
          candidate,
    ];
    if (members.isEmpty) {
      return;
    }
    final perMember = await mapPooled(members, concurrency, (member) async {
      try {
        return await client.implementations(
          member.uri,
          member.symbol.selectionRange.start,
        );
      } on LspRequestException catch (e) {
        recordProblem(
          _unresolvedSite,
          e,
          path: member.path,
          position: member.symbol.selectionRange.start,
          name: member.symbol.name,
        );
        return const <Location>[];
      }
    });
    for (final (i, member) in members.indexed) {
      final uses = elsewhere[_simpleName(member.symbol.name)]!;
      for (final loc in perMember[i]) {
        if (uses[_positionOfLocation(loc)] case final sites?) {
          usageByDecl.putIfAbsent(_positionOf(member), () => {}).addAll(sites);
        }
      }
    }
  }

  /// Whether [token] is a use of a local variable, which carries no
  /// modifiers.
  static bool _isLocalVariable(SemanticToken token) =>
      token.type == 'variable' && token.modifiers.isEmpty;

  /// Whether [token] declares something. The server marks a name in a `show`
  /// or `hide` combinator, after [lastKeyword], as a declaration too, though
  /// it uses what it names.
  static bool _isDeclaration(SemanticToken token, String? lastKeyword) =>
      token.isDeclaration && !const {'show', 'hide'}.contains(lastKeyword);

  static _DeclPosition _positionOfLocation(Location loc) => (
    SourceIndex.pathOf(loc.uri),
    loc.range.start.line,
    loc.range.start.character,
  );

  static _DeclPosition _positionOfSite(_Site site) =>
      (site.uri.toFilePath(), site.position.line, site.position.character);

  static String _simpleName(String name) =>
      name.contains('.') ? name.split('.').last : name;

  bool isRecovered(Candidate candidate) =>
      _usageByDecl.containsKey(_positionOf(candidate));

  /// These recoveries plus [other]'s; this one's sites come first.
  CrossLibraryReferences merged(CrossLibraryReferences other) =>
      CrossLibraryReferences._({
        ...other._usageByDecl,
        for (final MapEntry(key: decl, value: sites) in _usageByDecl.entries)
          decl: {...sites, ...?other._usageByDecl[decl]},
      });

  /// The recoveries less the usage sites (absolute path, position) that pass
  /// [test].
  CrossLibraryReferences whereNot(
    bool Function(String path, Position position) test,
  ) {
    bool keep(_Site site) => !test(site.uri.toFilePath(), site.position);
    return ._({
      for (final MapEntry(key: decl, value: sites) in _usageByDecl.entries)
        if (sites.where(keep).toSet() case final kept when kept.isNotEmpty)
          decl: kept,
    });
  }

  /// The first usage site that recovered [candidate], or `null` if not
  /// recovered.
  ({String path, int line, int character})? recoveredUsage(
    Candidate candidate,
  ) => recoveredUsages(candidate).firstOrNull;

  /// Every usage site that recovered [candidate].
  Iterable<({String path, int line, int character})> recoveredUsages(
    Candidate candidate,
  ) =>
      _usageByDecl[_positionOf(candidate)]?.map(
        (site) => (
          path: site.uri.toFilePath(),
          line: site.position.line,
          character: site.position.character,
        ),
      ) ??
      const .empty();

  /// Whether the use at [site] sits inside the very declaration it resolved
  /// to — a recursive call. `ReferenceClassifier.isSelfReference` discounts
  /// the same shape in the reference search; a probe must not recover it.
  static bool _isSelfUse(_Site site, Candidate declaration) {
    if (site.uri.toFilePath() != declaration.path) {
      return false;
    }
    return declaration.outline.range.contains(site.position);
  }

  static _DeclPosition _positionOf(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return (candidate.path, start.line, start.character);
  }

  static Iterable<({Uri uri, Position position, String name})> _collectSites({
    required SourceIndex sources,
    required String path,
    required Set<String> names,
    required bool Function(_DeclPosition position) skipped,
  }) sync* {
    if (sources.semanticTokens(path) case final tokens?) {
      final uri = File(path).uri;
      String? lastKeyword;
      for (final token in tokens) {
        if (token.isKeyword) {
          lastKeyword = token.text;
          continue;
        }
        // A declaration's own name resolves to itself, a reported reference
        // to what the server said, and a doc link is not a use. Neither is a
        // local variable: the server marks a use of a top-level variable or a
        // field as a property, and `this.field` as an instance variable.
        if (_memberTokenTypes.contains(token.type) &&
            !_isLocalVariable(token) &&
            !_isDeclaration(token, lastKeyword) &&
            names.contains(token.text) &&
            !skipped((path, token.line, token.character)) &&
            !sources.isDocLine(path, token.line)) {
          yield (uri: uri, position: token.start, name: token.text);
        }
      }
    }
  }
}
