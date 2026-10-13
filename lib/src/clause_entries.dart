/// Finds types named in `with` and `implements` clauses and builds the
/// removals that delete them from those clauses.
library;

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, SymbolKind;

/// The `kind` of a [CoupledRemoval] that removes a type from a `with` or
/// `implements` clause. The remover deletes exactly its range.
const clauseCutKind = SymbolKind.typeParameter;

/// A type named in a `with` or `implements` clause.
///
/// `path` is the file. `[clauseStart, clauseEnd)` are the offsets of the
/// clause, and `start` is the offset of the type's name. `keepsOne` is true for
/// the `with` clause of a class type alias, which must keep at least one mixin.
typedef ClauseEntry = ({
  String path,
  int clauseStart,
  int clauseEnd,
  int start,
  bool keepsOne,
});

final _clauseKeyword = RegExp(r'(with|implements)\s');

extension ClauseEntries on SourceIndex {
  /// Returns the clause entry at [loc] if it names [name] directly.
  ///
  /// Returns `null` for any other reference, such as a type annotation, an
  /// `extends` or `on` clause, or a prefixed or generic name.
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
    final declarationStart = offsetOf(path, declaration.range.start);
    if (start == null ||
        end == null ||
        clauseStart == null ||
        clauseEnd == null ||
        declarationStart == null) {
      return null;
    }
    final content = this.content(path);
    final keyword = _clauseKeyword.matchAsPrefix(content, clauseStart)?[1];
    if (start != offsetOf(path, loc.range.start) ||
        content.substring(start, end) != name ||
        keyword == null) {
      return null;
    }
    return (
      path: path,
      clauseStart: clauseStart,
      clauseEnd: clauseEnd,
      start: start,
      keepsOne:
          keyword == 'with' &&
          _isTypeAlias(content.substring(declarationStart, clauseStart)),
    );
  }

  /// Returns the removals that delete [entries] from their clauses, by entry.
  ///
  /// Adjacent entries are removed together with the comma after them. At the
  /// end of a clause, the comma before them is removed instead. If no entry is
  /// left, the whole clause is removed. Adjacent entries share one removal, so
  /// the code still compiles when only one of their types is removed.
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

  /// Does [clauseCuts] for the [cut] entries of one clause.
  Map<ClauseEntry, CoupledRemoval> _clauseCuts(
    List<ClauseEntry> cut,
    String rootPath,
  ) {
    final (:path, :clauseStart, :clauseEnd, start: _, :keepsOne) = cut.first;
    final content = this.content(path);
    final all = _entrySpans(content, clauseStart, clauseEnd);
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

/// Returns the `[start, end)` offsets of each type in a clause, without the
/// comments and whitespace around it.
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

/// Whether [header], the declaration text before its clause, belongs to a
/// class type alias such as `class A = B`.
///
/// It looks for an `=` outside brackets. The default values of a primary
/// constructor are always inside brackets.
bool _isTypeAlias(String header) {
  final code = stripComments(header);
  var depth = 0;
  for (var i = 0; i < code.length; i++) {
    switch (code[i]) {
      case '<' || '(' || '[' || '{':
        depth++;
      case '>' || ')' || ']' || '}':
        depth--;
      case '=' when depth == 0:
        return true;
    }
  }
  return false;
}

/// The offset just past the last non-whitespace character before [offset].
int _endOfPrevious(String content, int offset) {
  var i = offset;
  while (i > 0 && content[i - 1].trim().isEmpty) {
    i--;
  }
  return i;
}
