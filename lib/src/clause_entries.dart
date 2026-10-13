/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, Range, SelectionRange, SymbolKind;

/// The `kind` of a [CoupledRemoval] that removes a type from a `with` or
/// `implements` clause. The remover deletes exactly its range.
const clauseCutKind = SymbolKind.typeParameter;

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file and `clause` the range of the clause, keyword included.
/// `start` is the offset of the type's name. `keepsOne` is true for the `with`
/// clause of a class type alias, which must keep at least one mixin.
typedef ClauseEntry = ({String path, Range clause, int start, bool keepsOne});

const _clauseKeywords = {'with', 'implements'};

extension ClauseEntries on SourceIndex {
  /// Returns the `with` or `implements` clause that the type named at
  /// [position] is an entry of, or `null` if it is not one.
  SelectionRange? clauseAt(String path, Position position) {
    final clause = selectionRangeAt(path, position)?.parent;
    return clause != null && _keywordOf(path, clause.range) != null
        ? clause
        : null;
  }

  /// Returns the positions of the tokens in [clause] after its keyword,
  /// comments aside. Their syntax nodes tell the clause's entries apart.
  Iterable<Position> entryProbes(String path, Range clause) => [
    for (final token
        in semanticTokens(path)?.between(clause.start, clause.end).skip(1) ??
            const <SemanticToken>[])
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
    final clause = clauseAt(path, loc.range.start);
    final start = offsetOf(path, loc.range.start);
    if (type == null ||
        clause == null ||
        start == null ||
        type.range != loc.range ||
        semanticTokens(path)?.startingAt(loc.range.start)?.text != name) {
      return null;
    }
    return (
      path: path,
      clause: clause.range,
      start: start,
      keepsOne:
          _keywordOf(path, clause.range) == 'with' &&
          unit.childAt(loc.range.start)?.element.kind == .classTypeAlias,
    );
  }

  /// Returns the removals that delete [entries] from their clauses, by entry.
  ///
  /// An entry is removed together with the comma after it, or with the comma
  /// before it when it is last in the clause. When every entry goes, the whole
  /// clause goes, keyword included. Entries that are next to each other are
  /// cut as one range, so that their cuts never overlap. A clause whose
  /// entries have no syntax nodes is left alone.
  Map<ClauseEntry, CoupledRemoval> clauseCuts(
    Iterable<ClauseEntry> entries,
    String rootPath,
  ) => {
    for (final clause in entries.groupListsBy((e) => (e.path, e.clause)).values)
      ..._clauseCuts(clause, rootPath),
  };

  /// Does [clauseCuts] for the [cut] entries of one clause.
  Map<ClauseEntry, CoupledRemoval> _clauseCuts(
    List<ClauseEntry> cut,
    String rootPath,
  ) {
    final (:path, :clause, start: _, :keepsOne) = cut.first;
    final all = _entrySpans(path, clause);
    final clauseStart = offsetOf(path, clause.start);
    final clauseEnd = offsetOf(path, clause.end);
    if (all == null || clauseStart == null || clauseEnd == null) {
      return const {};
    }
    final byStart = {for (final entry in cut) entry.start: entry};
    final cuts = <ClauseEntry, CoupledRemoval>{};
    for (final (i, j) in _runs(all, byStart.containsKey)) {
      // Keep the mixins of a type alias if all of them would go.
      // `class A = B;` doesn't parse, and `extends B` would lose the
      // constructors that the alias forwards.
      if (keepsOne && i == 0 && j == all.length) {
        continue;
      }
      final (start, end) = j < all.length
          ? (all[i].start, all[j].start)
          : i > 0
          ? (all[i - 1].end, all[j - 1].end)
          : (
              (previousNonWhitespace(content(path), clauseStart) ?? -1) + 1,
              clauseEnd,
            );
      final range = _rangeOf(path, start, end);
      final removal = (
        filePath: relativePosix(path, rootPath),
        kind: clauseCutKind,
        range: range,
        fullRange: range,
        cut: null,
      );
      for (final span in all.sublist(i, j)) {
        cuts[byStart[span.start]!] = removal;
      }
    }
    return cuts;
  }

  /// Returns the `[start, end)` offsets of each entry of [clause], in order,
  /// as the syntax nodes under the clause give them. Returns `null` when a
  /// token in the clause has no syntax node.
  List<({int start, int end})>? _entrySpans(String path, Range clause) {
    final spans = <int, int>{};
    for (final position in entryProbes(path, clause)) {
      var node = selectionRangeAt(path, position);
      while (node != null && node.parent?.range != clause) {
        node = node.parent;
      }
      final start = node?.range.start.let((start) => offsetOf(path, start));
      final end = node?.range.end.let((end) => offsetOf(path, end));
      if (start == null || end == null) {
        return null;
      }
      spans[start] = end;
    }
    return [
      for (final start in spans.keys.toList()..sort())
        (start: start, end: spans[start]!),
    ];
  }

  /// Returns `with` or `implements` if [clause] starts with that keyword.
  String? _keywordOf(String path, Range clause) =>
      switch (semanticTokens(path)?.startingAt(clause.start)) {
        final token?
            when token.isKeyword && _clauseKeywords.contains(token.text) =>
          token.text,
        _ => null,
      };

  DeclarationRange _rangeOf(String path, int start, int end) {
    final starts = lineStarts(path);
    Position at(int offset) {
      final line = lowerBound(starts, offset + 1) - 1;
      return .new(line: line, character: offset - starts[line]);
    }

    return Range(start: at(start), end: at(end)).toDeclarationRange;
  }
}

/// Returns the `[i, j)` index ranges of consecutive [spans] whose start
/// [isCut] accepts.
Iterable<(int, int)> _runs(
  List<({int start, int end})> spans,
  bool Function(int start) isCut,
) sync* {
  var i = 0;
  while (i < spans.length) {
    if (!isCut(spans[i].start)) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < spans.length && isCut(spans[j].start)) {
      j++;
    }
    yield (i, j);
    i = j;
  }
}
