/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/list_cuts.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, Range, SymbolKind;

/// The `kind` of a [CoupledRemoval] that removes a type from a `with` or
/// `implements` clause. No symbol has it: it only tells these removals apart
/// from the others, which `--transitive` needs.
const clauseCutKind = SymbolKind.typeParameter;

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file and `clause` the range of the clause, keyword included.
/// `name` is the position of the type's name. `keepsOne` is true for the
/// `with` clause of a class type alias, which must keep at least one mixin.
typedef ClauseEntry = ({
  String path,
  Range clause,
  Position name,
  bool keepsOne,
});

const _clauseKeywords = {'with', 'implements'};

extension ClauseEntries on SourceIndex {
  /// Returns the position of each token in [clause] after its keyword,
  /// comments aside.
  ///
  /// [clauseCuts] needs the selection ranges at these positions to tell where
  /// each entry of the clause starts and ends.
  Iterable<Position> entryProbes(String path, Range clause) => [
    if (semanticTokens(path) case final tokens?)
      for (final token in tokens.between(clause.start, clause.end).skip(1))
        if (!token.isComment) token.start,
  ];

  /// Returns the clause entry at [loc] if it names [name] directly.
  ///
  /// [unit] is the outline of the file that holds [loc]. Returns `null` for
  /// any other reference, such as a type annotation, an `extends` or `on`
  /// clause, or a prefixed or generic name.
  ClauseEntry? clauseEntryAt(Location loc, String name, Outline unit) {
    final path = SourceIndex.pathOf(loc.uri);
    final type = selectionRangeAt(path, loc.range.start);
    final clause = type?.parent?.range;
    final keyword = clause?.let((clause) => _keywordOf(path, clause));
    if (type == null ||
        clause == null ||
        keyword == null ||
        type.range != loc.range ||
        semanticTokens(path)?.startingAt(loc.range.start)?.text != name) {
      return null;
    }
    return (
      path: path,
      clause: clause,
      name: loc.range.start,
      keepsOne:
          keyword == 'with' &&
          unit.childAt(loc.range.start)?.element.kind == .classTypeAlias,
    );
  }

  /// Returns the removals that delete [entries] from their clauses, by entry.
  ///
  /// Each group of adjacent entries goes with the comma after it, or, for a
  /// group that ends the clause, the comma before it. When every entry goes,
  /// the whole clause goes, keyword included. The entries of a clause whose
  /// selection ranges aren't cached get no removal.
  Map<ClauseEntry, CoupledRemoval> clauseCuts(
    Iterable<ClauseEntry> entries,
    String rootPath,
  ) => {
    for (final clause in entries.groupListsBy((e) => (e.path, e.clause)).values)
      ..._cutsInClause(clause, rootPath),
  };

  /// Returns [clauseCuts] for the [removed] entries of one clause.
  Map<ClauseEntry, CoupledRemoval> _cutsInClause(
    List<ClauseEntry> removed,
    String rootPath,
  ) {
    final (:path, :clause, name: _, :keepsOne) = removed.first;
    final all = _entriesIn(path, clause);
    final whole = _withSpaceBefore(path, clause);
    if (all == null || whole == null) {
      return const {};
    }
    final byName = {for (final entry in removed) entry.name: entry};
    final cuts = <ClauseEntry, CoupledRemoval>{};
    for (final (i, j, cut) in listCuts(
      all,
      (entry) => byName.containsKey(entry.start),
    )) {
      // Keep the mixins of a type alias if all of them would go.
      // `class A = B;` doesn't parse, and `extends B` would lose the
      // constructors that the alias forwards.
      if (cut == null && keepsOne) {
        continue;
      }
      final range = (cut ?? whole).toDeclarationRange;
      final removal = (
        filePath: relativePosix(path, rootPath),
        kind: clauseCutKind,
        range: range,
        fullRange: range,
        cut: range,
      );
      for (final entry in all.sublist(i, j)) {
        cuts[byName[entry.start]!] = removal;
      }
    }
    return cuts;
  }

  /// Returns the range of each entry of [clause], in source order: `B` and
  /// `C<int>` for `implements B, C<int>`. Returns `null` when a selection
  /// range it needs isn't cached.
  List<Range>? _entriesIn(String path, Range clause) {
    final entries = <Position, Range>{};
    for (final position in entryProbes(path, clause)) {
      var node = selectionRangeAt(path, position);
      while (node != null && node.parent?.range != clause) {
        node = node.parent;
      }
      if (node == null) {
        return null;
      }
      entries[node.range.start] = node.range;
    }
    return entries.values.toList();
  }

  /// Returns [clause] with the whitespace before it, so that removing it
  /// leaves `class A {`, not `class A  {`.
  Range? _withSpaceBefore(String path, Range clause) =>
      offsetOf(path, clause.start)?.let(
        (start) => Range(
          start: positionOf(
            path,
            (previousNonWhitespace(content(path), start) ?? -1) + 1,
          ),
          end: clause.end,
        ),
      );

  /// Returns `with` or `implements` if [clause] starts with that keyword.
  String? _keywordOf(String path, Range clause) =>
      switch (semanticTokens(path)?.startingAt(clause.start)) {
        final token?
            when token.isKeyword && _clauseKeywords.contains(token.text) =>
          token.text,
        _ => null,
      };
}
