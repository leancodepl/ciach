/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/list_cuts.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file, `clause` the clause, and `entry` the range of the
/// entry, like `M<int>`. `kind` is the kind of the type.
typedef ClauseEntry = ({
  String path,
  Clause clause,
  Range entry,
  SymbolKind kind,
});

extension ClauseEntries on FileSyntax {
  /// Returns the clause entry at [loc] if [loc] starts an entry of a `with` or
  /// `implements` clause, like `M` in `class A with M {}` or in
  /// `class A with M<int> {}`.
  ///
  /// [type] is the declaration of the type that [loc] references. Returns
  /// `null` for any other reference to [type]; see [FileSyntax.clauseAt].
  ClauseEntry? clauseEntryAt(Location loc, OutlineElement type) =>
      clauseAt(loc, type.name)?.let(
        (found) => (
          path: loc.path,
          clause: found.clause,
          entry: found.entry,
          kind: type.reportedKind!,
        ),
      );
}

/// Returns the removal `--remove` makes for each of [entries], by entry.
///
/// Each group of adjacent removed entries is cut out with the comma after it,
/// or, for a group that ends the clause, the comma before it. When every
/// entry goes, the whole clause goes, keyword included: `class A with M {}`
/// becomes `class A {}`. An entry gets no removal when it would take every
/// mixin of a mixin application class like `class A = B with M;`.
Map<ClauseEntry, CoupledRemoval> clauseCuts(
  Iterable<ClauseEntry> entries,
  String rootPath,
) => {
  for (final clause
      in entries.groupListsBy((e) => (e.path, e.clause.range)).values)
    ..._cutsInClause(clause, rootPath),
};

/// Returns [clauseCuts] for the entries of one clause.
///
/// [removed] holds the entries to remove, all from the same clause, like `C`
/// and `D` in `with C, D, E`.
Map<ClauseEntry, CoupledRemoval> _cutsInClause(
  List<ClauseEntry> removed,
  String rootPath,
) {
  final (:path, :clause, entry: _, kind: _) = removed.first;
  final filePath = relativePosix(path, rootPath);
  final byRange = {for (final entry in removed) entry.entry: entry};
  final cuts = <ClauseEntry, CoupledRemoval>{};
  for (final (i, j, cut) in listCuts(clause.entries, byRange.containsKey)) {
    // A mixin application class needs at least one mixin: `class A = B;`
    // doesn't compile. So when every mixin of one would go, none does.
    if (cut == null && clause.keepsOne) {
      continue;
    }
    final deleted = (cut ?? clause.whole).toDeclarationRange;
    for (final entry in clause.entries.sublist(i, j)) {
      final removedEntry = byRange[entry]!;
      final range = entry.toDeclarationRange;
      cuts[removedEntry] = (
        filePath: filePath,
        kind: removedEntry.kind,
        isClauseEntry: true,
        range: range,
        fullRange: range,
        cut: deleted,
      );
    }
  }
  return cuts;
}
