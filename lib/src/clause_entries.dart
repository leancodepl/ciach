/// Types named in `with` and `implements` clauses, and how to cut them out.
library;

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, SymbolKind;

/// The `kind` of a [CoupledRemoval] that cuts a type out of a `with` or
/// `implements` clause. The remover deletes exactly its range.
const clauseCutKind = SymbolKind.typeParameter;

/// A type named in a `with` or `implements` clause: the clause's file and
/// `[clauseStart, clauseEnd)` offsets, and the offset of the name.
typedef ClauseEntry = ({
  String path,
  int clauseStart,
  int clauseEnd,
  int start,
});

final _clauseKeyword = RegExp(r'(with|implements)\s');

extension ClauseEntries on SourceIndex {
  /// The clause entry reference [loc] names [name] by, or `null` for any other
  /// reference: a type annotation, an `extends` or `on` clause, a prefixed or
  /// generic name. A `with` clause counts only in a declaration with a body,
  /// so a class type alias (`class A = B with C;`) keeps its mixin.
  ClauseEntry? clauseEntryAt(Location loc, String name) {
    final path = SourceIndex.pathOf(loc.uri);
    final type = selectionRangeAt(path, loc.range.start);
    final clause = type?.parent;
    final declaration = clause?.parent;
    if (type == null || clause == null || declaration == null) {
      return null;
    }
    final start = offsetOf(path, type.range.start);
    final end = offsetOf(path, type.range.end);
    final clauseStart = offsetOf(path, clause.range.start);
    final clauseEnd = offsetOf(path, clause.range.end);
    final declarationEnd = offsetOf(path, declaration.range.end);
    if (start == null ||
        end == null ||
        clauseStart == null ||
        clauseEnd == null ||
        declarationEnd == null) {
      return null;
    }
    final content = this.content(path);
    final keyword = _clauseKeyword.matchAsPrefix(content, clauseStart)?[1];
    if (start != offsetOf(path, loc.range.start) ||
        content.substring(start, end) != name ||
        keyword == null ||
        (keyword == 'with' && content[declarationEnd - 1] != '}')) {
      return null;
    }
    return (
      path: path,
      clauseStart: clauseStart,
      clauseEnd: clauseEnd,
      start: start,
    );
  }

  /// The cuts that take [entries] out of their clauses, by entry. A run of
  /// entries goes with the comma after it, or before it when it ends the
  /// clause; a clause left empty goes whole. Each entry of a run gets the
  /// run's cut, so removing any one of their types alone still compiles.
  Map<ClauseEntry, CoupledRemoval> clauseCuts(
    Iterable<ClauseEntry> entries,
    String rootPath,
  ) => {
    for (final clause
        in entries
            .groupListsBy((e) => (e.path, e.clauseStart, e.clauseEnd))
            .values)
      ..._clauseCuts(clause, rootPath),
  };

  /// [clauseCuts] for the [cut] entries of one clause.
  Map<ClauseEntry, CoupledRemoval> _clauseCuts(
    List<ClauseEntry> cut,
    String rootPath,
  ) {
    final (:path, :clauseStart, :clauseEnd, start: _) = cut.first;
    final content = this.content(path);
    final all = _entrySpans(content, clauseStart, clauseEnd);
    final byStart = {for (final entry in cut) entry.start: entry};
    final cuts = <ClauseEntry, CoupledRemoval>{};
    var i = 0;
    while (i < all.length) {
      if (!byStart.containsKey(all[i].start)) {
        i++;
        continue;
      }
      var j = i + 1;
      while (j < all.length && byStart.containsKey(all[j].start)) {
        j++;
      }
      // Entries i to j - 1 are a run.
      final (start, end) = j < all.length
          ? (all[i].start, all[j].start)
          : i > 0
          ? (all[i - 1].end, all[j - 1].end)
          : (_endOfPrevious(content, clauseStart), clauseEnd);
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
      i = j;
    }
    return cuts;
  }

  DeclarationRange _rangeOf(String path, int start, int end) {
    Position at(int offset) {
      final starts = lineStarts(path);
      final line = lowerBound(starts, offset + 1) - 1;
      return Position(line: line, character: offset - starts[line]);
    }

    final (from, to) = (at(start), at(end));
    return (
      startLine: from.line,
      startColumn: from.character,
      endLine: to.line,
      endColumn: to.character,
    );
  }
}

/// The `[start, end)` offsets of the types a clause names, comments and
/// whitespace trimmed.
List<({int start, int end})> _entrySpans(
  String content,
  int clauseStart,
  int clauseEnd,
) {
  final code = stripComments(content.substring(clauseStart, clauseEnd));
  final keywordEnd = code.indexOf(RegExp(r'\s'));
  final spans = <({int start, int end})>[];
  void add(int from, int to) {
    final text = code.substring(from, to);
    final start = from + text.length - text.trimLeft().length;
    spans.add((
      start: clauseStart + start,
      end: clauseStart + start + text.trim().length,
    ));
  }

  var depth = 0;
  var from = keywordEnd;
  for (var i = keywordEnd; i < code.length; i++) {
    switch (code[i]) {
      case '<' || '(':
        depth++;
      case '>' || ')':
        depth--;
      case ',' when depth == 0:
        add(from, i);
        from = i + 1;
    }
  }
  add(from, code.length);
  return spans;
}

/// The offset just past the last non-whitespace character before [offset].
int _endOfPrevious(String content, int offset) {
  var i = offset;
  while (i > 0 && content[i - 1].trim().isEmpty) {
    i--;
  }
  return i;
}

extension CutsClauses on UnusedDeclaration {
  /// Whether removing this finding cuts it out of `with` and `implements`
  /// clauses that keep naming it until then.
  bool get cutsClauses =>
      coupledRemovals.any((removal) => removal.kind == clauseCutKind);
}
