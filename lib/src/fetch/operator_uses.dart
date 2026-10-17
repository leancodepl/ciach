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
import 'package:ciach/src/fetch/unsaved_changes.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

final _log = Logger('ciach.operator_uses');

const _lookupFailed = 'Could not look up the uses of operators; kept them all.';

const _keyword = 'operator';

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
}) async {
  if (operators.isEmpty) {
    return const {};
  }
  _log.info(
    'Looking up the uses of ${plural(operators.length, 'operator', 'operators')}…',
  );
  final changes = UnsavedChanges(client, sources);
  try {
    final hierarchies = await _hierarchiesOf(client, operators, analysisRoot);
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
    return usesOf;
  } on LspRequestException catch (e) {
    recordProblem(_lookupFailed, e, path: operators.first.path);
    return null;
  } finally {
    try {
      await changes.restore();
    } on LspRequestException catch (e) {
      recordProblem(_lookupFailed, e, path: operators.first.path);
    }
  }
}

/// The members of an override hierarchy of operators, and the candidates
/// among them.
typedef _Hierarchy = ({Set<_Member> members, List<Candidate> operators});

/// The name of an operator in a file: `+` in `operator +`.
typedef _Member = ({String path, Range name});

/// The override hierarchies of [operators] that have no member outside
/// [analysisRoot]. Two operators in one hierarchy share it.
Future<List<_Hierarchy>> _hierarchiesOf(
  LspClient client,
  List<Candidate> operators,
  String analysisRoot,
) async {
  final hierarchies = <_Hierarchy>[];
  for (final operator in operators) {
    final member = (path: operator.path, name: operator.symbol.selectionRange);
    if (hierarchies.firstWhereOrNull((h) => h.members.contains(member))
        case final hierarchy?) {
      hierarchy.operators.add(operator);
    } else if (await _membersOf(client, member, analysisRoot)
        case final members?) {
      hierarchies.add((members: members, operators: [operator]));
    }
  }
  return hierarchies;
}

/// [member] and every member that overrides it or that it overrides,
/// transitively, or `null` when one of them is outside [analysisRoot]. The
/// server names one overridden member for each member, so a class that
/// inherits an operator from two supertypes gets only one of them.
Future<Set<_Member>?> _membersOf(
  LspClient client,
  _Member member,
  String analysisRoot,
) async {
  final members = {member};
  final pending = [member];
  bool isInside(Location location) =>
      p.isWithin(analysisRoot, SourceIndex.pathOf(location.uri));
  while (pending.isNotEmpty) {
    final (:path, :name) = pending.removeLast();
    final uri = File(path).uri;
    final overridden = await client.superOf(uri, name.start);
    final related = [
      ?overridden,
      // The overrides of `Object.==` include every `==` in the SDK, so they
      // aren't looked up when the member is outside.
      if (overridden == null || isInside(overridden))
        ...await client.implementations(uri, name.start),
    ];
    for (final location in related) {
      if (!isInside(location)) {
        return null;
      }
      final found = (
        path: SourceIndex.pathOf(location.uri),
        name: location.range,
      );
      if (members.add(found)) {
        pending.add(found);
      }
    }
  }
  return members;
}

/// The content of each file of [members] with the members renamed, or `null`
/// when something other than whitespace, such as a comment, separates a
/// member's name from the `operator` keyword.
///
/// `operator +` becomes `o$$$$$$$$$`. The new name has the same length, so
/// every position stays the same, and the members get the same name, so each
/// still overrides the others.
Map<String, String>? _renamed(SourceIndex sources, Set<_Member> members) {
  final renamed = <String, String>{};
  for (final (:path, :name) in members) {
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
      r'o$'.padRight(nameEnd - keywordStart, r'$'),
    );
  }
  return renamed;
}
