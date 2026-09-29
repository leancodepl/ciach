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
import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reporter.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;

/// The CLI's own errors, warnings and narration; the library's come from the
/// other `ciach.*` loggers. All of it reaches the terminal through [_console].
final _log = Logger('ciach.cli');

/// Where the command's output goes, and what shows the log. Styled where the
/// terminal takes it until the options say otherwise.
var _console = Console.standard();

Future<void> main(List<String> arguments) async {
  // Returning an int from `main` does not set the process exit code in Dart,
  // so route the result through the global `exitCode`.
  try {
    exitCode = await _run(arguments);
  } on Object catch (e, st) {
    // Only what escapes [_run]'s own handling lands here, once the log is no
    // longer listened to.
    _console.write(
      describeFatalError(
        e,
        st,
        verbose: arguments.contains('--verbose') || arguments.contains('-v'),
        style: _console.errStyle,
      ),
    );
    exitCode = 2;
  }
}

Future<int> _run(List<String> arguments) async {
  Logger.root.level = _console.level;
  final logging = Logger.root.onRecord.listen((r) => _console.log(r));
  try {
    return await _runLogged(arguments);
  } finally {
    await logging.cancel();
    _console.clearProgress();
  }
}

Future<int> _runLogged(List<String> arguments) async {
  final parser = buildParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _log.severe(e.message);
    _console
      ..line()
      ..line(usage(parser));
    return 2;
  }

  if (args.flag('help')) {
    _console.report('${usage(parser)}\n');
    return 0;
  }

  if (args.flag('version')) {
    _console.report('ciach $ciachVersion\n');
    return 0;
  }

  final ignoreConfig = args.flag('no-config');
  final explicitConfig = args.option('config');
  if (ignoreConfig && explicitConfig != null) {
    _log.severe('--config cannot be combined with --no-config.');
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
      // Progress goes to stderr, so default it on only for a terminal.
      progressDefault: stderr.hasTerminal,
    );
  } on UsageException catch (e) {
    _log.severe(e.message);
    return 2;
  } on FormatException catch (e) {
    _log.severe(e.message);
    return 2;
  }

  _console = Console.standard(
    color: resolved.color,
    progress: resolved.showProgress,
    verbose: resolved.verbose,
  );
  Logger.root.level = _console.level;
  try {
    return await _analyze(resolved, configuration, config, projectDir);
  } on Object catch (e, st) {
    _log.severe('The run stopped.', e, st);
    return 2;
  }
}

/// Everything after the options are read: analyze, report, remove.
Future<int> _analyze(
  ResolvedOptions resolved,
  CiachConfiguration configuration,
  ConfigFile config,
  String projectDir,
) async {
  describeConfigSource(config, projectDir: projectDir).forEach(_log.fine);

  final rootDir = Directory(resolved.rootPath);
  if (!rootDir.existsSync()) {
    _log.severe('Path does not exist: ${resolved.rootPath}');
    return 2;
  }

  if (resolved.force && !resolved.remove) {
    _log.severe(
      'Skipping the removal prompt only makes sense when removing: --force (or `force: true`) requires --remove (or `remove: true`).',
    );
    return 2;
  }

  final format = resolved.format;

  // Up front: a missing SDK fails fast, and verbose shows the real `dart`.
  final String dartExecutable;
  try {
    dartExecutable = findDartExecutable(explicit: resolved.dartExecutable);
  } on DartSdkNotFoundException catch (e) {
    _log.severe(e.message);
    return 2;
  }

  // Built here so the checks below, --verbose and the run all read the same
  // normalized paths.
  final options = resolved.finderOptions(dartExecutable: dartExecutable);
  final rootPath = options.rootPath;

  if (options.analysisRootPath case final analysisRoot?) {
    if (!Directory(analysisRoot).existsSync()) {
      _log.severe('Analysis root does not exist: $analysisRoot');
      return 2;
    }
    // A root beside or below the scanned package would drop references, not
    // add them.
    if (!analysisRootContains(analysisRoot, rootPath)) {
      _log.severe(
        'The analysis root must contain the analyzed path: $analysisRoot does not contain $rootPath.',
      );
      return 2;
    }
  }

  describeSettings(
    configuration,
    resolved,
    options,
    dartExecutable: dartExecutable,
  ).forEach(_log.fine);

  final result = await Ciach(options).run();

  _log.fine(
    'Scanned ${result.filesScanned} file(s) and checked ${result.declarationsChecked} declaration(s) in ${result.elapsed.inMilliseconds}ms: ${result.unused.length} unused, ${result.docOnly.length} referenced only from doc comments.',
  );
  if (result.recoveredReferences.isNotEmpty) {
    _log.fine(
      'Kept ${result.recoveredReferences.length} declaration(s) the reference search called unused: the definition check found a use for each.',
    );
  }

  switch (format) {
    case 'json':
      _console.report('${Reporter.json(result)}\n');
    case 'github':
      // GitHub resolves annotation paths from the repo root, so prepend the
      // scan root's path from here.
      final prefix = p
          .split(p.relative(rootPath, from: Directory.current.path))
          .join('/');
      _log.fine("Prefixing annotation paths with '$prefix/'.");
      _console.report(Reporter.github(result, pathPrefix: prefix));
    case _:
      _console
        ..report('${Reporter.text(result, style: _console.outStyle)}\n')
        // Warnings go to stderr so they never corrupt text stdout; the json
        // and github formats carry them in-band instead.
        ..write(Reporter.warningsText(result, style: _console.errStyle))
        ..write(
          Reporter.problemsText(
            result,
            verbose: resolved.verbose,
            style: _console.errStyle,
          ),
        );
  }

  if (result.unused.isNotEmpty && resolved.remove) {
    await _removeUnused(result, rootPath, resolved);
  } else if (result.unused.isNotEmpty) {
    _log.fine('Leaving the findings in place; --remove was not given.');
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
) async {
  final style = _console.outStyle;

  // Report-only findings are left in place, so counting them would promise an
  // edit that never happens.
  final count = result.unused.whereNot((d) => d.removalBlocked).length;
  final plural = count == 1 ? '' : 's';

  final blocked = result.unused.length - count;
  if (blocked > 0) {
    _log.fine(
      'Skipping $blocked of ${result.unused.length} finding(s): removing them safely would need a source rewrite (see --unused-union-members and remove safety).',
    );
  }
  if (count == 0) {
    _log.warning(
      'Nothing removed: all $blocked finding${blocked == 1 ? ' is' : 's are'} '
      'unsafe to auto-remove — remove them manually.',
    );
    return;
  }

  var proceed = resolved.force;
  if (!proceed) {
    _log.fine('Asking for confirmation; pass --force to skip the prompt.');
    // The chosen --format may not be human-readable; show the findings
    // again so the confirmation prompt is never a shot in the dark.
    if (resolved.format != 'text') {
      _console.line(Reporter.text(result, style: _console.errStyle));
    }
    if (!stdin.hasTerminal) {
      _log.warning(
        'Refusing to remove declarations without a terminal to confirm on; pass --force to remove without asking.',
      );
      return;
    }
    _console.report(
      style.bold('Remove $count unused declaration$plural? [y/N] '),
    );
    proceed = switch (stdin.readLineSync()?.trim().toLowerCase()) {
      'y' || 'yes' => true,
      _ => false,
    };
  }

  if (!proceed) {
    _console.report('${style.hint('Skipped removal.')}\n');
    return;
  }

  if (_log.isLoggable(Level.FINE)) {
    final byFile = result.unused
        .whereNot((d) => d.removalBlocked)
        .groupFoldBy<String, int>((d) => d.filePath, (n, _) => (n ?? 0) + 1);
    for (final entry in byFile.entries) {
      _log.fine('Rewriting ${entry.key} (${entry.value} declaration(s)).');
    }
  }

  final removal = removeDeclarations(result.unused, rootPath);
  final filesChanged = removal.filesChanged;
  final left = blocked > 0
      ? ' ${style.yellow('$blocked left in place — unsafe to auto-remove.')}'
      : '';
  final deleted = removal.deletedFiles;
  final emptied = deleted.isEmpty
      ? ''
      : " Deleted ${deleted.length} now-empty file${deleted.length == 1 ? '' : 's'}: ${deleted.map((d) => d.filePath).join(', ')}.";
  _console.report(
    "${style.success("Removed $count unused declaration$plural from $filesChanged file${filesChanged == 1 ? '' : 's'}.")}$left$emptied ${style.hint("Run 'dart format' to tidy up spacing.")}\n",
  );
  for (final file in deleted) {
    _log.fine(
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
    _console.report('${style.bold('Note:')} $note\n');
  }
}
