/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reporter.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  // Returning an int from `main` does not set the process exit code in Dart,
  // so route the result through the global `exitCode`.
  try {
    exitCode = await _run(arguments);
  } on Object catch (e, st) {
    // Only what fails before the options are read lands here.
    stderr.write(
      describeFatalError(
        e,
        st,
        verbose: arguments.contains('--verbose') || arguments.contains('-v'),
      ),
    );
    exitCode = 2;
  }
}

Future<int> _run(List<String> arguments) async {
  final parser = buildParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(usage(parser));
    return 2;
  }

  if (args.flag('help')) {
    stdout.writeln(usage(parser));
    return 0;
  }

  if (args.flag('version')) {
    stdout.writeln('ciach $ciachVersion');
    return 0;
  }

  final ignoreConfig = args.flag('no-config');
  final explicitConfig = args.option('config');
  if (ignoreConfig && explicitConfig != null) {
    stderr.writeln('--config cannot be combined with --no-config.');
    return 2;
  }

  // The root named on the command line: a config file's own `path` can't decide
  // where that file is read from.
  final projectDir = args.rest.isEmpty ? '.' : args.rest.first;

  final ResolvedOptions resolved;
  final ConfigFile config;
  final CiachConfiguration configuration;
  try {
    config = .load(
      projectDir: projectDir,
      explicitPath: explicitConfig,
      ignore: ignoreConfig,
    );
    configuration = resolveConfiguration(args, config);
    resolved = resolveOptions(
      configuration,
      colorDefault: stdout.supportsAnsiEscapes,
      // Progress goes to stderr, so default it on only for a terminal.
      progressDefault: stderr.hasTerminal,
    );
  } on UsageException catch (e) {
    stderr.writeln(e.message);
    return 2;
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 2;
  }

  final log = resolved.verbose ? _VerboseLog() : null;
  try {
    return await _analyze(resolved, configuration, config, projectDir, log);
  } on Object catch (e, st) {
    if (resolved.showProgress) {
      stderr.writeln();
    }
    stderr.write(describeFatalError(e, st, verbose: resolved.verbose));
    return 2;
  }
}

/// Everything after the options are read: analyze, report, remove.
Future<int> _analyze(
  ResolvedOptions resolved,
  CiachConfiguration configuration,
  ConfigFile config,
  String projectDir,
  _VerboseLog? log,
) async {
  log?.writeAll(describeConfigSource(config, projectDir: projectDir));

  final rootDir = Directory(resolved.rootPath);
  if (!rootDir.existsSync()) {
    stderr.writeln('Path does not exist: ${resolved.rootPath}');
    return 2;
  }

  if (resolved.force && !resolved.remove) {
    stderr.writeln(
      'Skipping the removal prompt only makes sense when removing: --force (or `force: true`) requires --remove (or `remove: true`).',
    );
    return 2;
  }

  final format = resolved.format;
  final useColor = resolved.useColor;
  final showProgress = resolved.showProgress;

  // Up front: a missing SDK fails fast, and verbose shows the real `dart`.
  final String dartExecutable;
  try {
    dartExecutable = findDartExecutable(explicit: resolved.dartExecutable);
  } on DartSdkNotFoundException catch (e) {
    stderr.writeln(e.message);
    return 2;
  }

  // Built here so the checks below, --verbose and the run all read the same
  // normalized paths.
  final options = resolved.finderOptions(
    dartExecutable: dartExecutable,
    // Verbose keeps every phase line; progress overwrites one in place.
    onProgress: log?.write ?? (showProgress ? _ProgressPrinter().update : null),
  );
  final rootPath = options.rootPath;

  if (options.analysisRootPath case final analysisRoot?) {
    if (!Directory(analysisRoot).existsSync()) {
      stderr.writeln('Analysis root does not exist: $analysisRoot');
      return 2;
    }
    // A root beside or below the scanned package would drop references, not
    // add them.
    if (!analysisRootContains(analysisRoot, rootPath)) {
      stderr.writeln(
        'The analysis root must contain the analyzed path: $analysisRoot does not contain $rootPath.',
      );
      return 2;
    }
  }

  log?.writeAll(
    describeSettings(
      configuration,
      resolved,
      options,
      dartExecutable: dartExecutable,
    ),
  );

  final result = await Ciach(options).run();

  if (showProgress) {
    stderr.writeln();
  }

  log?.write(
    'Scanned ${result.filesScanned} file(s) and checked ${result.declarationsChecked} declaration(s) in ${result.elapsed.inMilliseconds}ms: ${result.unused.length} unused, ${result.docOnly.length} referenced only from doc comments.',
  );
  if (result.recoveredReferences.isNotEmpty) {
    log?.write(
      'Kept ${result.recoveredReferences.length} declaration(s) the reference search called unused: the definition check found a use for each.',
    );
  }

  switch (format) {
    case 'json':
      stdout.writeln(Reporter.json(result));
    case 'github':
      // GitHub resolves annotation paths from the repo root, so prepend the
      // scan root's path from here.
      final prefix = p
          .split(p.relative(rootPath, from: Directory.current.path))
          .join('/');
      log?.write("Prefixing annotation paths with '$prefix/'.");
      stdout.write(Reporter.github(result, pathPrefix: prefix));
    case _:
      stdout.writeln(Reporter.text(result, useColor: useColor));
      // Warnings go to stderr so they never corrupt text stdout; the json and
      // github formats carry them in-band instead.
      stderr
        ..write(Reporter.warningsText(result))
        ..write(
          Reporter.problemsText(
            result,
            verbose: resolved.verbose,
            useColor: useColor && stderr.supportsAnsiEscapes,
          ),
        );
  }

  if (result.unused.isNotEmpty && resolved.remove) {
    await _removeUnused(result, rootPath, resolved, format, useColor, log);
  } else if (result.unused.isNotEmpty) {
    log?.write('Leaving the findings in place; --remove was not given.');
  }

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

/// Reports what would be removed, confirms unless [ResolvedOptions.force], and
/// deletes the declarations from disk.
Future<void> _removeUnused(
  FinderResult result,
  String rootPath,
  ResolvedOptions resolved,
  String format,
  bool useColor,
  _VerboseLog? log,
) async {
  // Report-only findings are left in place, so counting them would promise an
  // edit that never happens.
  final count = result.unused.whereNot((d) => d.removalBlocked).length;
  final plural = count == 1 ? '' : 's';

  final blocked = result.unused.length - count;
  if (blocked > 0) {
    log?.write(
      'Skipping $blocked of ${result.unused.length} finding(s): removing them safely would need a source rewrite (see --unused-union-members and remove safety).',
    );
  }
  if (count == 0) {
    stdout.writeln(
      'Nothing removed: all $blocked finding${blocked == 1 ? ' is' : 's are'} '
      'unsafe to auto-remove — remove them manually.',
    );
    return;
  }

  var proceed = resolved.force;
  if (!proceed) {
    log?.write('Asking for confirmation; pass --force to skip the prompt.');
    // The chosen --format may not be human-readable; show the findings
    // again so the confirmation prompt is never a shot in the dark.
    if (format != 'text') {
      stderr.writeln(Reporter.text(result, useColor: useColor));
    }
    if (!stdin.hasTerminal) {
      stdout.writeln(
        'Refusing to remove declarations without a terminal to confirm on; pass --force to remove without asking.',
      );
      return;
    }
    stdout.write('Remove $count unused declaration$plural? [y/N] ');
    proceed = switch (stdin.readLineSync()?.trim().toLowerCase()) {
      'y' || 'yes' => true,
      _ => false,
    };
  }

  if (!proceed) {
    stdout.writeln('Skipped removal.');
    return;
  }

  if (log != null) {
    final byFile = result.unused
        .whereNot((d) => d.removalBlocked)
        .groupFoldBy<String, int>((d) => d.filePath, (n, _) => (n ?? 0) + 1);
    for (final entry in byFile.entries) {
      log.write('Rewriting ${entry.key} (${entry.value} declaration(s)).');
    }
  }

  final removal = removeDeclarations(result.unused, rootPath);
  final filesChanged = removal.filesChanged;
  final left = blocked > 0
      ? ' $blocked left in place — unsafe to auto-remove.'
      : '';
  final deleted = removal.deletedFiles;
  final emptied = deleted.isEmpty
      ? ''
      : " Deleted ${deleted.length} now-empty file${deleted.length == 1 ? '' : 's'}: ${deleted.map((d) => d.filePath).join(', ')}.";
  stdout.writeln(
    "Removed $count unused declaration$plural from $filesChanged file${filesChanged == 1 ? '' : 's'}.$left$emptied Run 'dart format' to tidy up spacing.",
  );
  for (final file in deleted) {
    log?.write(
      file.unlinkedFrom.isEmpty
          ? 'Deleted ${file.filePath}: nothing left but library/import/part-of lines.'
          : 'Deleted ${file.filePath}: nothing left but library/import/part-of lines. Dropped the directives naming it from ${file.unlinkedFrom.join(', ')}.',
    );
  }
  // Repeat any advisory hints: removing a declaration takes the reported line
  // that carried its hint with it.
  final removedHints = result.unused
      .where((d) => !d.removalBlocked && d.hint != null)
      .map((d) => '${d.qualifiedName}: ${d.hint}')
      .toSet();
  for (final note in removedHints) {
    stdout.writeln('Note: $note');
  }
}

/// Prints `--verbose` narration to stderr — not stdout, so `-f json` stays
/// machine-readable — one line per message, stamped with the elapsed time.
class _VerboseLog {
  final _stopwatch = Stopwatch()..start();

  /// Writes one stamped line.
  void write(String message) {
    final seconds = (_stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1);
    stderr.writeln('[${seconds.padLeft(5)}s] $message');
  }

  /// Writes a line per message.
  void writeAll(Iterable<String> messages) => messages.forEach(write);
}

/// Prints single-line, overwriting progress to stderr.
class _ProgressPrinter {
  int _lastLength = 0;

  void update(String message) {
    // Pad to overwrite any longer previous line, then return the cursor.
    final padded = message.padRight(_lastLength);
    _lastLength = message.length;
    stderr.write('\r$padded');
  }
}
