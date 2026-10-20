/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';

import 'package:ciach/src/model/finder_result.dart';

/// A machine-readable JSON report.
String jsonReport(FinderResult result) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    'summary': {
      'filesScanned': result.filesScanned,
      'declarationsChecked': result.declarationsChecked,
      'unusedCount': result.unused.length,
      'docOnlyCount': result.docOnly.length,
      'emptyFileCount': result.emptyFiles.length,
      'emptyVariantCount': result.emptyVariants.length,
      'elapsedMs': result.elapsed.inMilliseconds,
    },
    'unused': [for (final decl in result.unused) decl.toJson()],
    'docOnly': [for (final decl in result.docOnly) decl.toJson()],
    'emptyFiles': result.emptyFiles,
    'emptyVariants': result.emptyVariants,
    'emptiedContainers': [
      for (final (:filePath, :name) in result.emptiedContainers)
        {'filePath': filePath, 'name': name},
    ],
    'warnings': [for (final w in result.recoveredReferences) w.toJson()],
    'problems': [for (final problem in result.problems) problem.toJson()],
  });
}
