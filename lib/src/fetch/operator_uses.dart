/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds the uses of operators, such as `a + b`, `a[i]` and `case < 0`.
///
/// The reference search misses most of them. So each operator is renamed in
/// unsaved copies of the files, together with the operators that it overrides
/// and that override it. Every compile error that this causes is a use.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/operator_hierarchies.dart';
import 'package:ciach/src/fetch/unsaved_changes.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.operator_uses');

const _lookupFailed = 'Could not look up the uses of operators; kept them all.';

/// The text that replaces the `operator` keyword. It has the same length, so
/// no position moves. Every member of a hierarchy gets the same text, so they
/// still override each other.
const _renamedKeyword = r'o$$$$$$$';

/// Returns the uses of each of [operators], or `null` when a request fails.
///
/// A use counts for every operator in the same hierarchy. An operator is left
/// out when its hierarchy reaches outside [analysisRoot], as `Object.==` does,
/// because the uses there can't be found.
Future<Map<Candidate, List<Location>>?> findOperatorUses({
  required LspClient client,
  required SourceIndex sources,
  required List<Candidate> operators,
  required String analysisRoot,
  required int concurrency,
}) async {
  if (operators.isEmpty) {
    return const {};
  }
  _log.info(
    'Looking up the uses of ${plural(operators.length, 'operator', 'operators')}…',
  );
  try {
    final hierarchies = await operatorHierarchies(
      client,
      operators,
      analysisRoot: analysisRoot,
      concurrency: concurrency,
    );
    final renamedContentOf = {
      for (final hierarchy in hierarchies)
        hierarchy: ?await _renamedContent(client, sources, hierarchy.members),
    };
    // Each hierarchy gets its own round: once `a + b` is an error, the server
    // reports no error at the `*` of `(a + b) * c`.
    return await withUnsavedChanges(client, sources, (changes) async {
      final usesOf = <Candidate, List<Location>>{};
      for (final (i, MapEntry(key: hierarchy, value: renamed))
          in renamedContentOf.entries.indexed) {
        _log.fine('[${i + 1}/${renamedContentOf.length}] `${hierarchy.name}`');
        changes.send(renamed);
        final uses = [
          for (final MapEntry(key: path, value: ranges)
              in (await changes.usesByPath()).entries)
            for (final range in ranges)
              Location(uri: File(path).uri.toString(), range: range),
        ];
        for (final operator in hierarchy.candidates) {
          usesOf[operator] = uses;
        }
      }
      return usesOf;
    });
  } on LspRequestException catch (e) {
    recordProblem(_lookupFailed, e, path: operators.first.path);
    return null;
  }
}

/// Returns the content of the files that declare [members], with each
/// `operator` keyword replaced by [_renamedKeyword] and each name by spaces.
/// Returns `null` when a name doesn't follow an `operator` keyword.
Future<Map<String, String>?> _renamedContent(
  LspClient client,
  SourceIndex sources,
  Set<Location> members,
) async {
  final replacements = <String, List<({int offset, String text})>>{};
  for (final member in members) {
    final path = SourceIndex.pathOf(member.uri);
    final tokens =
        sources.semanticTokens(path) ??
        await client.semanticTokens(.parse(member.uri), sources.lines(path));
    if ((
          tokens.lastNonCommentBefore(member.range.start),
          sources.offsetsOf(path, member.range),
        )
        case (
          SemanticToken(isKeyword: true, text: 'operator', :final start),
          final name?,
        )) {
      (replacements[path] ??= []).addAll([
        (offset: sources.offsetOf(path, start)!, text: _renamedKeyword),
        (offset: name.start, text: ' ' * (name.end - name.start)),
      ]);
    } else {
      return null;
    }
  }
  return {
    for (final MapEntry(key: path, value: inFile) in replacements.entries)
      path: sources.contentWith(path, inFile),
  };
}
