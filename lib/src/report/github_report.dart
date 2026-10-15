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

/// [GitHub Actions workflow commands][] — one `::warning` annotation per
/// unused finding and empty file (surfacing them inline on the PR diff and
/// Checks tab) and one lower-severity `::notice` per doc-only finding.
///
/// Annotation paths are resolved relative to the repository root. [pathPrefix]
/// (POSIX, `/`-separated) is prepended to each finding's path so that scans of
/// a sub-directory still point at the right file; it defaults to `.` (the
/// scan root is the repository root).
///
/// [GitHub Actions workflow commands]: https://docs.github.com/actions/reference/workflow-commands-for-github-actions
String githubReport(FinderResult result, {String pathPrefix = '.'}) {
  final buffer = StringBuffer();
  for (final (:check, :file, :line, :column, :message) in annotationsOf(
    result,
    pathPrefix,
  )) {
    final properties = [
      'file=${_escapeProperty(file)}',
      ?line?.let((line) => 'line=$line'),
      ?column?.let((column) => 'col=$column'),
      'title=${_escapeProperty(check.title)}',
    ];
    buffer.writeln(
      "::${check.notice ? 'notice' : 'warning'} ${properties.join(',')}::${_escapeData(message)}",
    );
  }
  return buffer.toString();
}

// Escaping per the workflow-command spec.
String _escapeData(String value) => value
    .replaceAll('%', '%25')
    .replaceAll('\r', '%0D')
    .replaceAll('\n', '%0A');

String _escapeProperty(String value) =>
    _escapeData(value).replaceAll(':', '%3A').replaceAll(',', '%2C');
