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
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

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
/// as the reference search counts a call of a method through a subclass. The
/// files stay changed in [changes] until the caller restores them.
///
/// An operator is left out when its hierarchy has a member outside
/// [analysisRoot], such as `Object.==`, because the uses of that member can't
/// be found and the SDK calls `==` without any code that names it. `null` when
/// a request to the server failed, so that the uses are unknown.
Future<Map<Candidate, List<Location>>?> findOperatorUses({
  required LspClient client,
  required SourceIndex sources,
  required UnsavedChanges changes,
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
    final rounds = _rounds([
      for (final hierarchy in hierarchies)
        if (_renamedNames(sources, hierarchy.members) case final names?)
          (hierarchy: hierarchy, names: names),
    ]);
    final usesOf = <Candidate, List<Location>>{};
    for (final (i, round) in rounds.indexed) {
      _log.fine(
        '[${i + 1}/${rounds.length}] ${round.map((r) => '`${r.hierarchy.name}`').join(', ')}',
      );
      changes.show(
        _renamed(sources, [
          for (final (:names, hierarchy: _) in round) ...names,
        ]),
      );
      final errors = await changes.newErrors();
      for (final (:hierarchy, names: _) in round) {
        final uses = _usesOf(hierarchy, round, errors, sources);
        for (final operator in hierarchy.operators) {
          usesOf[operator] = uses;
        }
      }
    }
    return usesOf;
  } on LspRequestException catch (e) {
    recordProblem(_lookupFailed, e, path: operators.first.path);
    return null;
  }
}

/// A hierarchy, with the offsets that its rename replaces in each file.
typedef _Renamable = ({OperatorHierarchy hierarchy, List<_RenamedName> names});

/// The text that a rename replaces, from the `operator` keyword to the end of
/// the name: `operator +`.
typedef _RenamedName = ({String path, int start, int end});

/// The uses of [hierarchy] among [errors], the new errors by file of the
/// [round] that renamed it. In a round of several hierarchies, an error at an
/// operator belongs to the hierarchy with that name, and any other error to
/// each of them.
List<Location> _usesOf(
  OperatorHierarchy hierarchy,
  List<_Renamable> round,
  Map<String, Set<Range>> errors,
  SourceIndex sources,
) => [
  for (final MapEntry(key: path, value: ranges) in errors.entries)
    for (final range in ranges)
      if (sources.textOf(path, range) case final text
          when text == hierarchy.name ||
              round.none((other) => other.hierarchy.name == text))
        .new(uri: File(path).uri.toString(), range: range),
];

/// [hierarchies] grouped into rounds that rename them together.
///
/// Most hierarchies get a round of their own. After `a + b` fails, the server
/// doesn't know the type of the expression, so the server reports no error at
/// the `*` of `(a + b) * c`, which would hide that use if `*` were renamed in
/// the same round. A comparison such as `a < b` gives a `bool`, though, and no
/// class, mixin, enum or extension type that declares an operator is a
/// supertype of `bool`. So the hierarchies whose operators all return `bool`
/// share rounds, one for each name, such as `<` and `>=`, so that the text of
/// an error tells which of them it belongs to.
List<List<_Renamable>> _rounds(List<_Renamable> hierarchies) {
  final shared = <List<_Renamable>>[];
  final own = <List<_Renamable>>[];
  for (final renamable in hierarchies) {
    if (!_returnsBool(renamable.hierarchy)) {
      own.add([renamable]);
    } else if (shared.firstWhereOrNull(
          (round) => round.none(
            (other) => other.hierarchy.name == renamable.hierarchy.name,
          ),
        )
        case final round?) {
      round.add(renamable);
    } else {
      shared.add([renamable]);
    }
  }
  return [...own, ...shared];
}

/// Whether the candidates of [hierarchy] are members of classes, mixins or
/// enums and return `bool`. The members that they override return a
/// supertype of `bool`, and those that override them return `bool`.
bool _returnsBool(OperatorHierarchy hierarchy) => hierarchy.operators.every(
  (operator) =>
      !operator.isExtensionMember &&
      operator.outline.element.returnType == 'bool',
);

/// The text that renaming [members] replaces, or `null` when something other
/// than whitespace, such as a comment, separates a member's name from the
/// `operator` keyword.
List<_RenamedName>? _renamedNames(
  SourceIndex sources,
  Set<DeclarationName> members,
) {
  final names = <_RenamedName>[];
  for (final member in members) {
    final path = member.path;
    // The outline gives the range of the name, but not of the keyword.
    final beforeName = sources
        .content(path)
        .substring(0, sources.offsetOf(path, member.range.start))
        .trimRight();
    if (!beforeName.endsWith(_keyword)) {
      return null;
    }
    names.add((
      path: path,
      start: beforeName.length - _keyword.length,
      end: sources.offsetOf(path, member.range.end)!,
    ));
  }
  return names;
}

/// The content of each file of [names] with each of them replaced by
/// [_newName].
Map<String, String> _renamed(SourceIndex sources, List<_RenamedName> names) => {
  for (final MapEntry(key: path, value: inFile)
      in names.groupListsBy((name) => name.path).entries)
    path: inFile.fold(
      sources.content(path),
      (text, name) => text.replaceRange(
        name.start,
        name.end,
        _newName.padRight(name.end - name.start),
      ),
    ),
};
