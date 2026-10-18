/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Applies a rule's fix to the code of a test.
library;

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/protocol/protocol_common.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

/// Creates the producer of a fix, such as `ReplaceWithLet.new`.
typedef FixProducer = CorrectionProducer Function({
  required CorrectionProducerContext context,
});

extension FixTesting on AnalysisRuleTest {
  /// Returns the change that [producer]'s fix makes for each [lint]
  /// diagnostic in [code], leaving out the fixes that edit nothing.
  Future<List<SourceChange>> fixChanges(
    String code,
    LintCode lint,
    FixProducer producer,
  ) async {
    final file = newFile(testFile.path, code);
    final unit = await resolveFile(file.path);
    final library = await unit.session.getResolvedLibrary(
      file.path,
    ) as ResolvedLibraryResult;
    return [
      for (final diagnostic in unit.diagnostics.where(
        (diagnostic) => diagnostic.diagnosticCode == lint,
      ))
        if (await _changeFor(producer, library, unit, diagnostic)
            case final change when change.getFileEdit(file.path) != null)
          change,
    ];
  }

  /// Returns [code] after [producer]'s fix is applied to each [lint]
  /// diagnostic in it, or `null` when the fix edits nothing.
  Future<String?> applyFixes(
    String code,
    LintCode lint,
    FixProducer producer,
  ) async {
    // Two fixes that add the same import insert the same edit; it is applied
    // once.
    final edits = {
      for (final change in await fixChanges(code, lint, producer))
        ...change.getFileEdit(testFile.path)!.edits,
    };
    if (edits.isEmpty) {
      return null;
    }
    // Later edits first, so that earlier offsets stay valid.
    final ordered = edits.toList()
      ..sort((a, b) => b.offset.compareTo(a.offset));
    return SourceEdit.applySequence(code, ordered);
  }

  Future<SourceChange> _changeFor(
    FixProducer producer,
    ResolvedLibraryResult library,
    ResolvedUnitResult unit,
    Diagnostic diagnostic,
  ) async {
    final builder = ChangeBuilder(session: unit.session);
    await producer(
      context: .createResolved(
        libraryResult: library,
        unitResult: unit,
        diagnostic: diagnostic,
        selectionOffset: diagnostic.offset,
        selectionLength: diagnostic.length,
      ),
    ).compute(builder);
    return builder.sourceChange;
  }
}
