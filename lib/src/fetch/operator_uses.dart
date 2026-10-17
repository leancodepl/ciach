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
///
/// Each hierarchy is renamed in a round of its own. After `a + b` fails, the
/// type of the expression is unknown, so the server reports no error at the
/// `*` of `(a + b) * c`, which would hide that use if `*` were renamed in the
/// same round.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/operator_hierarchies.dart';
import 'package:ciach/src/fetch/unsaved_changes.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.operator_uses');

const _lookupFailed = 'Could not look up the uses of operators; kept them all.';

const _keyword = 'operator';

/// The name that replaces `operator +` and the other operator names. It is as
/// long as the shortest of them, `operator~`, and spaces pad it to the length
/// of a longer one, so that every position stays the same. Every member of a
/// hierarchy gets this name, so each still overrides the others.
const _newName = r'o$$$$$$$$';

/// The uses of each of [operators] that ciach can check, by candidate. A use
/// of any member of an operator's override hierarchy counts for each member,
/// as the reference search counts a call of a method through a subclass.
///
/// An operator is left out when its hierarchy has a member outside
/// [analysisRoot], such as `Object.==`, because the uses of that member can't
/// be found and the SDK calls `==` without any code that names it. `null` when
/// a request to the server failed, so that the uses are unknown.
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
  final changes = UnsavedChanges(client, sources);
  try {
    final hierarchies = await operatorHierarchies(
      client,
      operators,
      analysisRoot: analysisRoot,
      concurrency: concurrency,
    );
    final usesOf = <Candidate, List<Location>>{};
    for (final (i, hierarchy) in hierarchies.indexed) {
      final renamed = _renamed(sources, hierarchy.members);
      if (renamed == null) {
        continue;
      }
      _log.fine(
        '[${i + 1}/${hierarchies.length}] `${hierarchy.operators.first.symbol.name}`',
      );
      for (final MapEntry(key: path, value: text) in renamed.entries) {
        changes.change(path, text);
      }
      changes.restoreExcept(renamed.keys.toSet());
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
    await changes.restore();
    return usesOf;
  } on LspRequestException catch (e) {
    recordProblem(_lookupFailed, e, path: operators.first.path);
    return null;
  } finally {
    // After a failure, the files are restored without waiting for their
    // analysis, which would need another request to the server.
    changes.revert();
  }
}

/// The content of each file of [members] with the members renamed to
/// [_newName], or `null` when something other than whitespace, such as a
/// comment, separates a member's name from the `operator` keyword.
Map<String, String>? _renamed(
  SourceIndex sources,
  Set<OperatorDeclaration> members,
) {
  final renamed = <String, String>{};
  for (final OperatorDeclaration(:path, :name) in members) {
    final text = renamed[path] ?? sources.content(path);
    final nameEnd = sources.offsetOf(path, name.end)!;
    // The outline gives the range of the name, but not of the keyword.
    final beforeName = text
        .substring(0, sources.offsetOf(path, name.start))
        .trimRight();
    if (!beforeName.endsWith(_keyword)) {
      return null;
    }
    final keywordStart = beforeName.length - _keyword.length;
    renamed[path] = text.replaceRange(
      keywordStart,
      nameEnd,
      _newName.padRight(nameEnd - keywordStart),
    );
  }
  return renamed;
}
