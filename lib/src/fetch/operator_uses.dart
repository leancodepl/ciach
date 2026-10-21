/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds the uses of operators: `a + b`, `-a`, `a[i]`, `a[i] = v`, `a += b`
/// and the relational patterns `case < 0` and `case >= 10`.
///
/// The reference search misses them. It finds a use of an operator only in
/// the library that declares it, it finds no relational pattern at all, and
/// for an override such as `==`, it lists the uses of every member that the
/// operator overrides, also those in the SDK. But the server reports a compile
/// error at each use once the operator is gone. So the operator and every
/// member of its override hierarchy are renamed in unsaved copies of their
/// files, and every new error is a use.
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

/// The name that replaces the `operator` keyword. It has the length of the
/// keyword, and spaces replace the operator's name, so that every position
/// stays the same. Every member of a hierarchy gets this name, so each still
/// overrides the others.
const _newName = r'o$$$$$$$';

/// The uses of each of [operators] that ciach can check, by candidate, or
/// `null` when a request to the server failed, so that the uses are unknown.
/// A use of any member of an operator's override hierarchy counts for each
/// member, as the reference search counts a call of a method through a
/// subclass.
///
/// An operator is left out when its hierarchy has a member outside
/// [analysisRoot], such as `Object.==`, because the uses of that member can't
/// be found and the SDK calls `==` without any code that names it. It is left
/// out too when the server sends no `operator` keyword before the name of a
/// member.
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
    final renamedOf = {
      for (final hierarchy in hierarchies)
        hierarchy: ?await _renamed(client, sources, hierarchy.members),
    };
    // Each hierarchy is renamed in a round of its own: after `a + b` fails,
    // the server doesn't know the type of the expression, so it reports no
    // error at the `*` of `(a + b) * c`.
    return await withUnsavedChanges(client, sources, (changes) async {
      final usesOf = <Candidate, List<Location>>{};
      for (final (i, MapEntry(key: hierarchy, value: renamed))
          in renamedOf.entries.indexed) {
        _log.fine('[${i + 1}/${renamedOf.length}] `${hierarchy.name}`');
        changes.show(renamed);
        final uses = [
          for (final MapEntry(key: path, value: ranges)
              in (await changes.newErrors()).entries)
            for (final range in ranges)
              Location(uri: File(path).uri.toString(), range: range),
        ];
        for (final operator in hierarchy.operators) {
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

/// The content of each file that declares one of [members], with the
/// `operator` keyword of each member replaced by [_newName] and its name by
/// spaces, or `null` when the token before a member's name, apart from
/// comments, is not the `operator` keyword.
Future<Map<String, String>?> _renamed(
  LspClient client,
  SourceIndex sources,
  Set<DeclarationName> members,
) async {
  final replacements = <String, List<({int offset, String text})>>{};
  for (final member in members) {
    final path = member.path;
    final tokens =
        sources.semanticTokens(path) ??
        await client.semanticTokens(member.uri, sources.lines(path));
    if ((
          tokens.lastCodeBefore(member.range.start),
          sources.offsetsOf(path, member.range),
        )
        case (
          SemanticToken(isKeyword: true, text: 'operator', :final start),
          final name?,
        )) {
      (replacements[path] ??= []).addAll([
        (offset: sources.offsetOf(path, start)!, text: _newName),
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
