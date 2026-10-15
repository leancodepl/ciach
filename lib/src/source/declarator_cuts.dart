/// Works out the text `--remove` deletes for a field or top-level variable.
///
/// One statement can declare several variables, like `int a = 1, b = 2;`.
/// Removing some of them cuts each out with a comma; removing all of them
/// deletes the whole statement. The ranges come from the analysis server's
/// selection ranges, so comments and line breaks in the statement don't
/// matter.
library;

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/list_cuts.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, Range, SelectionRange;

/// A field or top-level variable, identified by its file and the position of
/// its name.
typedef DeclaratorAt = ({String path, Position name});

extension DeclaratorCuts on SourceIndex {
  /// Returns, grouped by file, the positions of the other variable names
  /// declared in the same statements as [declarators].
  ///
  /// [declaratorCuts] needs the selection ranges at these positions to tell
  /// where each variable of a statement starts and ends. Names inside a
  /// variable's own initializer, like a closure's parameters, are left out.
  /// The selection range at each of [declarators] must already be cached.
  Map<String, Set<Position>> otherDeclaratorNames(
    Iterable<DeclaratorAt> declarators,
  ) {
    final probes = <String, Set<Position>>{};
    for (final (:path, :name) in declarators) {
      if (selectionRangeAt(path, name) case SelectionRange(
        :final range,
        parent: SelectionRange(range: final list),
      )) {
        probes
            .putIfAbsent(path, () => {})
            .addAll(_namesIn(path, list).whereNot(range.contains));
      }
    }
    return probes;
  }

  /// Returns the position of every name declared within [range] of [path],
  /// according to its semantic tokens.
  List<Position> _namesIn(String path, Range range) => [
    if (semanticTokens(path) case final tokens?)
      for (final token in tokens.between(range.start, range.end))
        if (token.modifiers.contains('declaration')) token.start,
  ];

  /// Returns the range `--remove` deletes for each of [declarators].
  ///
  /// When every variable a statement declares is in [declarators], the range
  /// is the whole statement, with its doc comment, annotations and `;`.
  /// Otherwise each group of adjacent removed variables is cut out with the
  /// comma after it, or, for a group that ends the statement, the comma before
  /// it. The range is `null` when a selection range it depends on isn't
  /// cached.
  Map<DeclaratorAt, DeclarationRange?> declaratorCuts(
    Iterable<DeclaratorAt> declarators,
  ) {
    final cuts = <DeclaratorAt, DeclarationRange?>{};
    final byList = <(String, Range), Map<Position, DeclaratorAt>>{};
    for (final declarator in declarators) {
      final (:path, :name) = declarator;
      if (selectionRangeAt(path, name) case SelectionRange(
        :final range,
        parent: SelectionRange(range: final list),
      )) {
        byList.putIfAbsent((path, list), () => {})[range.start] = declarator;
      } else {
        cuts[declarator] = null;
      }
    }
    for (final MapEntry(key: (path, list), value: removed) in byList.entries) {
      cuts.addAll(_cutsInStatement(path, list, removed));
    }
    return cuts;
  }

  /// Returns [declaratorCuts] for the variables of one statement.
  ///
  /// [list] is the range of the statement's declaration list, like
  /// `int a = 1, b = 2` without the `;`. [removed] maps the start of each
  /// removed variable, like `a = 1`, to that variable.
  Map<DeclaratorAt, DeclarationRange?> _cutsInStatement(
    String path,
    Range list,
    Map<Position, DeclaratorAt> removed,
  ) {
    final siblings = _declaratorsIn(path, list);
    final statement = selectionRangeAt(
      path,
      removed.values.first.name,
    )?.parent?.parent?.range;
    if (siblings == null ||
        statement == null ||
        removed.keys.any((start) => siblings.none((s) => s.start == start))) {
      return {for (final declarator in removed.values) declarator: null};
    }
    final cuts = <DeclaratorAt, DeclarationRange?>{};
    for (final (i, j, cut) in listCuts(
      siblings,
      (sibling) => removed.containsKey(sibling.start),
    )) {
      // When every variable goes, the whole statement goes.
      final range = (cut ?? statement).toDeclarationRange;
      for (final sibling in siblings.sublist(i, j)) {
        cuts[removed[sibling.start]!] = range;
      }
    }
    return cuts;
  }

  /// Returns the range of each variable in the declaration list at [list], in
  /// source order: `a = 1` and `b = 2` for `int a = 1, b = 2`. Returns `null`
  /// when a selection range it needs isn't cached.
  List<Range>? _declaratorsIn(String path, Range list) {
    final declarators = <Range>[];
    for (final name in _namesIn(path, list)) {
      // Skip names inside the previous variable's initializer, like a
      // closure's parameters. Their selection ranges were never fetched.
      if (declarators.lastOrNull?.contains(name) ?? false) {
        continue;
      }
      final node = selectionRangeAt(path, name);
      if (node == null) {
        return null;
      }
      // A name whose node isn't directly in the list, like a parameter of a
      // function type, isn't one of its variables.
      if (node.parent?.range == list) {
        declarators.add(node.range);
      }
    }
    return declarators;
  }
}
