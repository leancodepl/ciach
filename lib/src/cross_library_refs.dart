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
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
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

    final byPosition = <_DeclPosition, Candidate>{
      for (final candidate in candidates) _positionOf(candidate): candidate,
    };
    final declarations = byPosition.keys.toSet();

    final sites = [
      for (final path in sources.scannedPaths)
        ..._collectSites(
          sources: sources,
          path: path,
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
        if (byPosition[pos] case final declaration?
            when !_isSelfUse(sites[i], declaration)) {
          usageByDecl.putIfAbsent(pos, () => sites[i]);
        }
      }
    }
    return CrossLibraryReferences._(usageByDecl);
  }

  bool isRecovered(Candidate candidate) =>
      _usageByDecl.containsKey(_positionOf(candidate));

  CrossLibraryReferences merged(CrossLibraryReferences other) =>
      other._usageByDecl.isEmpty
      ? this
      : CrossLibraryReferences._({...other._usageByDecl, ..._usageByDecl});

  /// Only the recoveries whose usage site (absolute path, position) [keep]
  /// accepts.
  CrossLibraryReferences where(bool Function(String path, Position) keep) =>
      _usageByDecl.isEmpty
      ? this
      : CrossLibraryReferences._({
          for (final MapEntry(key: decl, value: site) in _usageByDecl.entries)
            if (keep(site.uri.toFilePath(), site.position)) decl: site,
        });

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

  /// Whether the use at [site] sits inside the very declaration it resolved
  /// to — a recursive call. [ReferenceClassifier.isSelfReference] discounts
  /// the same shape in the reference search; a probe must not recover it.
  static bool _isSelfUse(_Site site, Candidate declaration) {
    if (site.uri.toFilePath() != declaration.path) {
      return false;
    }
    final range = declaration.outline.range;
    return range.start.atOrBefore(site.position) &&
        site.position.atOrBefore(range.end);
  }

  static _DeclPosition _positionOf(Candidate candidate) {
    final start = candidate.symbol.selectionRange.start;
    return (candidate.path, start.line, start.character);
  }

  static Iterable<_Site> _collectSites({
    required SourceIndex sources,
    required String path,
    required Set<String> names,
    required Set<_DeclPosition> declarations,
  }) sync* {
    if (sources.semanticTokens(path) case final tokens?) {
      final uri = File(path).uri;
      for (final token in tokens) {
        // A declaration's own name resolves to itself; a doc link is not a use.
        if (_memberTokenTypes.contains(token.type) &&
            names.contains(token.text) &&
            !declarations.contains((path, token.line, token.character)) &&
            !sources.isDocLine(path, token.line)) {
          yield (uri: uri, position: token.start);
        }
      }
    }
  }
}
