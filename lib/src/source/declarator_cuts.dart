/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Works out the text `--remove` deletes for a field or top-level variable.
///
/// One statement can declare several variables, like `int a = 1, b = 2;`.
/// Removing some of them cuts each out with a comma; removing all of them
/// deletes the whole statement. The ranges come from the syntax nodes of the
/// statement, so comments and line breaks in it don't matter.
library;

import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/list_cuts.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/symbols.dart';

/// A field or top-level variable, identified by its file and the offset of
/// its name.
typedef DeclaratorAt = ({String path, int name});

extension DeclaratorCuts on FileSyntax {
  /// Returns the range `--remove` deletes for each of [declarators].
  ///
  /// When every variable a statement declares is in [declarators], the range
  /// is the whole statement, with its doc comment, annotations and `;`.
  /// Otherwise each group of adjacent removed variables is cut out with the
  /// comma after it, or, for a group that ends the statement, the comma before
  /// it. The range is `null` when no variable's name starts at the position,
  /// such as in a file that can't be parsed.
  Map<DeclaratorAt, DeclarationRange?> declaratorCuts(
    Iterable<DeclaratorAt> declarators,
  ) {
    final cuts = <DeclaratorAt, DeclarationRange?>{};
    final byStatement =
        <
          (String, Range),
          ({VariableStatement statement, Map<Range, DeclaratorAt> removed})
        >{};
    for (final declarator in declarators) {
      final (:path, :name) = declarator;
      if (declaratorAt(path, name) case (
        :final statement,
        declarator: final range,
      )) {
        byStatement.putIfAbsent(
          (path, statement.range),
          () => (statement: statement, removed: {}),
        ).removed[range] = declarator;
      } else {
        cuts[declarator] = null;
      }
    }
    return {
      ...cuts,
      for (final (:statement, :removed) in byStatement.values)
        ..._cutsInStatement(statement, removed),
    };
  }
}

/// Returns [DeclaratorCuts.declaratorCuts] for the variables of one
/// statement. [removed] maps the range of each removed variable, like
/// `a = 1`, to that variable.
Map<DeclaratorAt, DeclarationRange> _cutsInStatement(
  VariableStatement statement,
  Map<Range, DeclaratorAt> removed,
) => {
  for (final (i, j, cut) in listCuts(
    statement.declarators,
    removed.containsKey,
  ))
    // When every variable goes, the whole statement goes.
    for (final declarator in statement.declarators.sublist(i, j))
      removed[declarator]!: (cut ?? statement.range).toDeclarationRange,
};
