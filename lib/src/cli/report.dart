import 'dart:io';

import 'package:ciach/src/cli/ci.dart';
import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/report/azure_report.dart';
import 'package:ciach/src/report/checkstyle_report.dart';
import 'package:ciach/src/report/github_report.dart';
import 'package:ciach/src/report/gitlab_report.dart';
import 'package:ciach/src/report/json_report.dart';
import 'package:ciach/src/report/sarif_report.dart';
import 'package:ciach/src/report/teamcity_report.dart';
import 'package:ciach/src/report/text_report.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.cli');

/// Logs how much was scanned and what [result] found.
void logSummary(FinderResult result) {
  final counts = [
    '${result.unused.length} unused',
    '${result.docOnly.length} referenced only from doc comments',
    if (result.allEmptyFiles.isNotEmpty)
      plural(result.allEmptyFiles.length, 'empty file', 'empty files'),
    if (result.recoveredReferences.isNotEmpty)
      '${result.recoveredReferences.length} recovered',
    if (result.problems.isNotEmpty) '${result.problems.length} not analyzed',
  ];
  _log.fine(
    'Scanned ${plural(result.filesScanned, 'file', 'files')} and checked '
    '${plural(result.declarationsChecked, 'declaration', 'declarations')} in '
    '${result.elapsed.inMilliseconds}ms: ${counts.join(', ')}.',
  );
}

/// Writes [result] to stdout in the format [resolved] asks for.
void writeReport(
  Console console,
  FinderResult result,
  ResolvedOptions resolved,
  String rootPath,
) {
  switch (resolved.format) {
    case 'text':
      console.output(
        textReport(result, style: console.outStyle, verbose: resolved.verbose),
      );
    case 'json':
      console.output(jsonReport(result));
    case final format:
      // The other formats are read by tools that resolve paths from the
      // repository root, so prepend the scan root's path from there: from the
      // checkout the CI service names, or else from here.
      final repositoryRoot =
          checkoutRoot(
            rootPath,
            checkoutDir: resolved.ci?.checkoutVariable?.let(
              (variable) => Platform.environment[variable],
            ),
          ) ??
          Directory.current.path;
      final prefix = p
          .split(p.relative(rootPath, from: repositoryRoot))
          .join('/');
      _log.config(
        "Prefixing report paths with '$prefix/', the scan root's path from $repositoryRoot.",
      );
      final report = switch (format) {
        'azure' => azureReport,
        'teamcity' => teamCityReport,
        'sarif' => sarifReport,
        'checkstyle' => checkstyleReport,
        'gitlab' => gitlabReport,
        'github' => githubReport,
        _ => throw StateError("No reporter for the format '$format'."),
      };
      console.output(report(result, pathPrefix: prefix));
  }
}

/// The exit code for [result]: 1 when `--set-exit-if-changed` and a counted
/// finding or an empty file remain, else 0.
int exitCodeFor(FinderResult result, ResolvedOptions resolved) =>
    resolved.setExitIfChanged &&
        (result.unused.isNotEmpty || result.allEmptyFiles.isNotEmpty)
    ? 1
    : 0;
