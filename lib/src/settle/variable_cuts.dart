/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/declarator_cuts.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, SymbolKind;

/// The text `--remove` deletes for a round's removable fields and top-level
/// variables, worked out from the analysis server's selection ranges.
final class VariableCuts {
  VariableCuts({required ReferenceFetch fetch, required SourceIndex sources})
    : _fetch = fetch,
      _sources = sources;

  final ReferenceFetch _fetch;
  final SourceIndex _sources;

  /// Returns [unused] with [UnusedDeclaration.cut] set on each removable field
  /// and top-level variable, both findings and coupled removals. A cut that is
  /// already set, as on a declaring parameter, stays.
  ///
  /// It first fetches the selection ranges this needs, for these variables
  /// only. The cuts are worked out in one call, so two removed variables of
  /// one statement are cut as one. A finding whose own cut, or the cut of a
  /// variable coupled to it, can't be worked out becomes report-only, with
  /// [Verdict.noCutHint].
  Future<List<UnusedDeclaration>> withCuts(
    LspClient client,
    List<UnusedDeclaration> unused,
    String rootPath,
  ) async {
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
    bool needsCut(SymbolKind kind, DeclarationRange? cut) =>
        declaratorKinds.contains(kind) && cut == null;

    final removable = unused.whereNot((finding) => finding.removalBlocked);
    final declarators = [
      for (final finding in removable) ...[
        if (needsCut(finding.kind, finding.cut)) ofFinding(finding),
        for (final coupled in finding.coupledRemovals)
          if (needsCut(coupled.kind, coupled.cut)) ofCoupled(coupled),
      ],
    ];
    await _fetch.fetchSelectionRanges(
      client,
      declarators.groupFoldBy(
        (declarator) => declarator.path,
        (names, declarator) => (names ?? <Position>{})..add(declarator.name),
      ),
    );
    await _fetch.fetchSelectionRanges(
      client,
      _sources.otherDeclaratorNames(declarators),
    );
    final cuts = _sources.declaratorCuts(declarators);
    UnusedDeclaration withCuts(UnusedDeclaration finding) {
      final cut = needsCut(finding.kind, finding.cut)
          ? cuts[ofFinding(finding)]
          : finding.cut;
      final coupledRemovals = [
        for (final coupled in finding.coupledRemovals)
          if (needsCut(coupled.kind, coupled.cut))
            (
              filePath: coupled.filePath,
              kind: coupled.kind,
              range: coupled.range,
              fullRange: coupled.fullRange,
              cut: cuts[ofCoupled(coupled)],
            )
          else
            coupled,
      ];
      if (needsCut(finding.kind, cut) ||
          coupledRemovals.any(
            (coupled) => needsCut(coupled.kind, coupled.cut),
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
