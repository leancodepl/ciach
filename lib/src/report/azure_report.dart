/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/report/annotations.dart';
import 'package:ciach/src/util/extensions.dart';

/// [Azure Pipelines logging commands][] — one `task.logissue` warning per
/// finding, which the run's summary lists with its file and line. Azure has
/// no severity below a warning, so doc-only findings are warnings too.
///
/// [pathPrefix] is prepended to each path, as in `githubReport`.
///
/// [Azure Pipelines logging commands]: https://learn.microsoft.com/azure/devops/pipelines/scripts/logging-commands
String azureReport(FinderResult result, {String pathPrefix = '.'}) {
  final buffer = StringBuffer();
  for (final (:check, :file, :line, :column, :message) in annotationsOf(
    result,
    pathPrefix,
  )) {
    final properties = [
      'type=warning',
      'sourcepath=${_escapeAzure(file, property: true)}',
      ?line?.let((line) => 'linenumber=$line'),
      ?column?.let((column) => 'columnnumber=$column'),
    ];
    buffer.writeln(
      "##vso[task.logissue ${properties.join(';')}]${_escapeAzure('${check.title}: $message')}",
    );
  }
  return buffer.toString();
}

// Escaping per the Azure Pipelines agent, which unescapes `%AZP25` last.
String _escapeAzure(String value, {bool property = false}) {
  final data = value
      .replaceAll('%', '%AZP25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');
  return property ? data.replaceAll(';', '%3B').replaceAll(']', '%5D') : data;
}
