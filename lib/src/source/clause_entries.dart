/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/list_cuts.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, Range, SymbolKind;

/// The `kind` of a [CoupledRemoval] that removes a type from a `with` or
/// `implements` clause, like `M` from `class A with M {}`. It borrows the kind
/// of a type parameter, which no other removal has, so `--transitive` can tell
/// these removals apart.
const clauseCutKind = SymbolKind.typeParameter;

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file and `clause` the range of the clause, keyword included.
/// `name` is the position of the type's name. `keepsOne` is true for the
/// `with` clause of a mixin application class, like `class A = B with M;`,
/// which must keep at least one mixin.
typedef ClauseEntry = ({
  String path,
  Range clause,
  Position name,
  bool keepsOne,
});

const _clauseKeywords = {'with', 'implements'};

extension ClauseEntries on SourceIndex {
  /// Returns the start of each name in [clause] after its keyword: `B`, `C` and
  /// `int` for `implements B, C<int>`. Comments are left out.
  ///
  /// [clauseCuts] needs the selection ranges at these positions to tell where
  /// each entry of the clause starts and ends.
  Iterable<Position> namesInClause(String path, Range clause) => [
    if (semanticTokens(path) case final tokens?)
      for (final token in tokens.between(clause.start, clause.end).skip(1))
        if (!token.isComment) token.start,
  ];

  /// Returns the clause entry at [loc] if [loc] starts an entry of a `with` or
  /// `implements` clause, like `M` in `class A with M {}` or in
  /// `class A with M<int> {}`.
  ///
  /// [unit] is the outline of the file that holds [loc]. Returns `null` for any
  /// other reference to [name], such as a type annotation, an `extends` or `on`
  /// clause, `p.M`, or a type argument like the `M` in `implements List<M>`.
  ClauseEntry? clauseEntryAt(Location loc, String name, Outline unit) {
    final path = SourceIndex.pathOf(loc.uri);
    final type = selectionRangeAt(path, loc.range.start);
    final clause = type?.parent?.range;
    final keyword = clause?.let((clause) => _keywordOf(path, clause));
    if (type == null ||
        clause == null ||
        keyword == null ||
        type.range.start != loc.range.start ||
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

  /// Returns the removal `--remove` makes for each of [entries], by entry.
  ///
  /// Each group of adjacent removed entries is cut out with the comma after it,
  /// or, for a group that ends the clause, the comma before it. When every
  /// entry goes, the whole clause goes, keyword included: `class A with M {}`
  /// becomes `class A {}`. An entry gets no removal when the selection ranges
  /// of its clause aren't cached, or when it would take every mixin of a mixin
  /// application class like `class A = B with M;`.
  Map<ClauseEntry, CoupledRemoval> clauseCuts(
    Iterable<ClauseEntry> entries,
    String rootPath,
  ) => {
    for (final clause in entries.groupListsBy((e) => (e.path, e.clause)).values)
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
      // A mixin application class needs at least one mixin: `class A = B;`
      // doesn't compile. So when every mixin of one would go, none does.
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
    for (final position in namesInClause(path, clause)) {
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
  ///
  /// When a `//` comment ends the line before the clause, the range starts on
  /// the clause's own line instead. Otherwise the code after the clause would
  /// end up inside the comment.
  Range? _withSpaceBefore(String path, Range clause) {
    final start = offsetOf(path, clause.start);
    if (start == null) {
      return null;
    }
    final text = content(path);
    final before = previousNonWhitespace(text, start);
    final from = switch (before) {
      null => 0,
      final before when _endsLineComment(path, before) =>
        text.indexOf('\n', before) + 1,
      final before => before + 1,
    };
    return Range(start: positionOf(path, from), end: clause.end);
  }

  /// Whether the character at [offset] of [path] is in a `//` comment.
  bool _endsLineComment(String path, int offset) {
    final position = positionOf(path, offset);
    return semanticTokens(path)
            ?.between(
              .new(line: position.line, character: 0),
              .new(line: position.line, character: position.character + 1),
            )
            .any((token) => token.isComment && token.text.startsWith('//')) ??
        false;
  }

  /// Returns `with` or `implements` if [clause] starts with that keyword.
  String? _keywordOf(String path, Range clause) =>
      switch (semanticTokens(path)?.startingAt(clause.start)) {
        SemanticToken(isKeyword: true, :final text)
            when _clauseKeywords.contains(text) =>
          text,
        _ => null,
      };
}
