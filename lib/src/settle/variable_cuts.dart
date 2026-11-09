/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/declarator_cuts.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';

/// The text `--remove` deletes for a round's removable fields and top-level
/// variables, worked out from their syntax nodes.
final class VariableCuts {
  VariableCuts(this._sources);

  final SourceIndex _sources;

  /// Returns [unused] with [UnusedDeclaration.cut] set on each removable field
  /// and top-level variable, both findings and coupled removals.
  ///
  /// The cuts are worked out in one call, so two removed variables of one
  /// statement are cut as one. A finding whose own cut, or the cut of a
  /// variable coupled to it, can't be worked out becomes report-only, with
  /// [Verdict.noCutHint].
  List<UnusedDeclaration> withCuts(
    List<UnusedDeclaration> unused,
    String rootPath,
  ) {
    DeclaratorAt at(String filePath, int line, int column) => (
      path: absoluteUnder(filePath, rootPath),
      name: .new(line: line, character: column),
    );
    DeclaratorAt ofFinding(UnusedDeclaration finding) =>
        at(finding.filePath, finding.line - 1, finding.column - 1);
    DeclaratorAt ofCoupled(CoupledRemoval coupled) => at(
      coupled.filePath,
      coupled.range.startLine,
      coupled.range.startColumn,
    );
    bool isDeclarator(SymbolKind kind) => declaratorKinds.contains(kind);

    final removable = unused.whereNot((finding) => finding.removalBlocked);
    final declarators = [
      for (final finding in removable) ...[
        if (isDeclarator(finding.kind)) ofFinding(finding),
        for (final coupled in finding.coupledRemovals)
          if (isDeclarator(coupled.kind)) ofCoupled(coupled),
      ],
    ];
    final cuts = _sources.declaratorCuts(declarators);
    UnusedDeclaration withCuts(UnusedDeclaration finding) {
      final cut = isDeclarator(finding.kind) ? cuts[ofFinding(finding)] : null;
      final coupledRemovals = [
        for (final coupled in finding.coupledRemovals)
          if (isDeclarator(coupled.kind))
            (
              filePath: coupled.filePath,
              kind: coupled.kind,
              isClauseEntry: coupled.isClauseEntry,
              range: coupled.range,
              fullRange: coupled.fullRange,
              cut: cuts[ofCoupled(coupled)],
            )
          else
            coupled,
      ];
      bool lacksCut(SymbolKind kind, DeclarationRange? cut) =>
          isDeclarator(kind) && cut == null;
      if (lacksCut(finding.kind, cut) ||
          coupledRemovals.any(
            (coupled) => lacksCut(coupled.kind, coupled.cut),
          )) {
        return finding.copyWith(removalBlocked: true, hint: Verdict.noCutHint);
      }
      return finding.copyWith(cut: cut, coupledRemovals: coupledRemovals);
    }

    return [
      for (final finding in unused)
        if (finding.removalBlocked) finding else withCuts(finding),
    ];
  }
}
