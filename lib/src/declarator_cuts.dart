/// Where `--remove` cuts the fields and top-level variables it deletes, read
/// from the analyzer's syntax nodes rather than from the text.
library;

import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, Range;

/// A field or top-level variable: its file and the start of its name.
typedef DeclaratorAt = ({String path, Position name});

extension DeclaratorCuts on SourceIndex {
  /// Returns, by file, the names declared in the statements of
  /// [declarators], whose syntax nodes tell their declarators apart.
  Map<String, Set<Position>> declaratorProbes(
    Iterable<DeclaratorAt> declarators,
  ) {
    final probes = <String, Set<Position>>{};
    for (final (:path, :name) in declarators) {
      probes
          .putIfAbsent(path, () => {})
          .addAll(
            selectionRangeAt(
                  path,
                  name,
                )?.parent?.range.let((list) => _namesIn(path, list)) ??
                const [],
          );
    }
    return probes;
  }

  /// The starts of the names declared in [range] of [path].
  List<Position> _namesIn(String path, Range range) => [
    for (final token
        in semanticTokens(path)?.between(range.start, range.end) ??
            const <SemanticToken>[])
      if (token.modifiers.contains('declaration')) token.start,
  ];

  /// Returns the range `--remove` deletes for each of [declarators].
  ///
  /// When a statement loses every declarator, the whole statement goes, with
  /// its doc comment, annotations and `;`. Otherwise each run of removed
  /// declarators goes with the comma after it, or with the comma before it
  /// when it ends the list. A declarator gets `null` when a syntax node it
  /// needs was not fetched.
  Map<DeclaratorAt, DeclarationRange?> declaratorCuts(
    Iterable<DeclaratorAt> declarators,
  ) {
    final cuts = <DeclaratorAt, DeclarationRange?>{};
    final byList = <(String, Range), List<DeclaratorAt>>{};
    for (final declarator in declarators) {
      final (:path, :name) = declarator;
      if (selectionRangeAt(path, name)?.parent?.range case final list?) {
        byList.putIfAbsent((path, list), () => []).add(declarator);
      } else {
        cuts[declarator] = null;
      }
    }
    for (final MapEntry(key: (path, list), value: removed) in byList.entries) {
      cuts.addAll(_cutsIn(path, list, removed));
    }
    return cuts;
  }

  /// Does [declaratorCuts] for the [removed] declarators of the declarator
  /// list at [list].
  Map<DeclaratorAt, DeclarationRange?> _cutsIn(
    String path,
    Range list,
    List<DeclaratorAt> removed,
  ) {
    final siblings = _declaratorsIn(path, list);
    final byStart = {
      for (final declarator in removed)
        ?selectionRangeAt(path, declarator.name)?.range.start: declarator,
    };
    final statement = selectionRangeAt(
      path,
      removed.first.name,
    )?.parent?.parent?.range;
    if (siblings == null ||
        statement == null ||
        byStart.length != removed.length ||
        byStart.keys.any((start) => siblings.none((s) => s.start == start))) {
      return {for (final declarator in removed) declarator: null};
    }
    if (byStart.length == siblings.length) {
      final cut = statement.toDeclarationRange;
      return {for (final declarator in removed) declarator: cut};
    }
    final cuts = <DeclaratorAt, DeclarationRange?>{};
    for (final (i, j) in _runs(siblings, byStart.containsKey)) {
      final cut = j < siblings.length
          ? Range(start: siblings[i].start, end: siblings[j].start)
          : Range(start: siblings[i - 1].end, end: siblings[j - 1].end);
      for (final sibling in siblings.sublist(i, j)) {
        cuts[byStart[sibling.start]!] = cut.toDeclarationRange;
      }
    }
    return cuts;
  }

  /// Returns the ranges of the declarators in the declarator list at [list],
  /// in order, or `null` when one of their syntax nodes was not fetched.
  List<Range>? _declaratorsIn(String path, Range list) {
    final declarators = <Range>[];
    for (final name in _namesIn(path, list)) {
      final node = selectionRangeAt(path, name);
      if (node == null) {
        return null;
      }
      // A name declared in an initializer, such as a closure's parameter,
      // sits deeper.
      if (node.parent?.range == list) {
        declarators.add(node.range);
      }
    }
    return declarators;
  }
}

/// Returns the `[i, j)` index ranges of consecutive [ranges] whose start
/// [isCut] accepts.
Iterable<(int, int)> _runs(
  List<Range> ranges,
  bool Function(Position start) isCut,
) sync* {
  var i = 0;
  while (i < ranges.length) {
    if (!isCut(ranges[i].start)) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < ranges.length && isCut(ranges[j].start)) {
      j++;
    }
    yield (i, j);
    i = j;
  }
}
