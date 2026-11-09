/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/list_cuts.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file and `clause` the range of the clause, keyword included.
/// `name` is the position of the type's name, and `kind` the kind of the
/// type. `keepsOne` is true for the `with` clause of a mixin application
/// class, like `class A = B with M;`, which must keep at least one mixin.
typedef ClauseEntry = ({
  String path,
  Range clause,
  Position name,
  SymbolKind kind,
  bool keepsOne,
});

const _clauseKeywords = {'with', 'implements'};

extension ClauseEntries on SourceIndex {
  /// Returns the start of each name in [clause] after its keyword: `B`, `C` and
  /// `int` for `implements B, C<int>`. Comments are left out.
  Iterable<Position> _namesInClause(String path, Range clause) => [
    if (semanticTokens(path) case final tokens?)
      for (final token in tokens.between(clause.start, clause.end).skip(1))
        if (!token.isComment) token.start,
  ];

  /// Returns the clause entry at [loc] if [loc] starts an entry of a `with` or
  /// `implements` clause, like `M` in `class A with M {}` or in
  /// `class A with M<int> {}`.
  ///
  /// [type] is the declaration of the type that [loc] references, and [unit]
  /// the outline of the file that holds [loc]. Returns `null` for any other
  /// reference to [type], such as a type annotation, an `extends` or `on`
  /// clause, `p.M`, or a type argument like the `M` in `implements List<M>`.
  ClauseEntry? clauseEntryAt(Location loc, OutlineElement type, Outline unit) {
    final path = loc.path;
    final node = selectionRangeAt(path, loc.range.start);
    final clause = node?.parent?.range;
    final keyword = clause?.let((clause) => _keywordOf(path, clause));
    if (node == null ||
        clause == null ||
        keyword == null ||
        node.range.start != loc.range.start ||
        semanticTokens(path)?.startingAt(loc.range.start)?.text != type.name) {
      return null;
    }
    return (
      path: path,
      clause: clause,
      name: loc.range.start,
      kind: type.reportedKind!,
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
  /// becomes `class A {}`. An entry gets no removal when its file can't be
  /// parsed, or when it would take every mixin of a mixin application class
  /// like `class A = B with M;`.
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
    final (:path, :clause, name: _, kind: _, :keepsOne) = removed.first;
    final all = _entriesIn(path, clause);
    final whole = _withSpaceBefore(path, clause);
    if (all == null || whole == null) {
      return const {};
    }
    final filePath = relativePosix(path, rootPath);
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
      final deleted = (cut ?? whole).toDeclarationRange;
      for (final entry in all.sublist(i, j)) {
        final range = entry.toDeclarationRange;
        final removed = byName[entry.start]!;
        cuts[removed] = (
          filePath: filePath,
          kind: removed.kind,
          isClauseEntry: true,
          range: range,
          fullRange: range,
          cut: deleted,
        );
      }
    }
    return cuts;
  }

  /// Returns the range of each entry of [clause], in source order: `B` and
  /// `C<int>` for `implements B, C<int>`. Returns `null` when the file can't
  /// be parsed.
  List<Range>? _entriesIn(String path, Range clause) {
    final entries = <Position, Range>{};
    for (final position in _namesInClause(path, clause)) {
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
    return .new(start: positionOf(path, from), end: clause.end);
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
