import 'dart:io';

import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reporter.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.cli');

/// Logs how much was scanned and what [result] found.
void logSummary(FinderResult result) {
  final counts = [
    '${result.unused.length} unused',
    '${result.docOnly.length} referenced only from doc comments',
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
    case 'json':
      console.output(Reporter.json(result));
    case 'github':
      // GitHub resolves annotation paths from the repo root, so prepend the
      // scan root's path from here.
      final prefix = p
          .split(p.relative(rootPath, from: Directory.current.path))
          .join('/');
      _log.config("Prefixing annotation paths with '$prefix/'.");
      console.output(Reporter.github(result, pathPrefix: prefix));
    case _:
      console.output(
        Reporter.text(
          result,
          style: console.outStyle,
          verbose: resolved.verbose,
        ),
      );
  }
}

/// The exit code for [result]: 1 when `--set-exit-if-changed` and a counted
/// finding remain, else 0.
int exitCodeFor(FinderResult result, ResolvedOptions resolved) {
  if (resolved.setExitIfChanged) {
    // Public findings are still reported; --no-fail-public only drops them from the exit code.
    final failing = resolved.failPublic
        ? result.unused
        : result.unused.where((d) => d.isPrivate);
    if (failing.isNotEmpty) {
      return 1;
    }
  }
  return 0;
}
