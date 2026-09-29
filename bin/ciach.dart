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

/// The CLI's own `--verbose` narration; the library's comes from `ciach.*`.
final _log = Logger('ciach.cli');

Future<void> main(List<String> arguments) async {
  // Returning an int from `main` does not set the process exit code in Dart,
  // so route the result through the global `exitCode`.
  try {
    exitCode = await _run(arguments);
  } on Object catch (e, st) {
    // Only what fails before the options are read lands here.
    final console = Console.standard();
    console.write(
      describeFatalError(
        e,
        st,
        verbose: arguments.contains('--verbose') || arguments.contains('-v'),
        style: console.errStyle,
      ),
    );
    exitCode = 2;
  }
}

Future<int> _run(List<String> arguments) async {
  // Until the options say otherwise: styled where the terminal takes it.
  var console = Console.standard();
  final parser = buildParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    console
      ..error(e.message)
      ..line()
      ..line(usage(parser));
    return 2;
  }

  if (args.flag('help')) {
    console.report('${usage(parser)}\n');
    return 0;
  }

  if (args.flag('version')) {
    console.report('ciach $ciachVersion\n');
    return 0;
  }

  final ignoreConfig = args.flag('no-config');
  final explicitConfig = args.option('config');
  if (ignoreConfig && explicitConfig != null) {
    console.error('--config cannot be combined with --no-config.');
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
    console.error(e.message);
    return 2;
  } on FormatException catch (e) {
    console.error(e.message);
    return 2;
  }

  console = Console.standard(
    color: resolved.color,
    progress: resolved.showProgress,
    verbose: resolved.verbose,
  );
  final logging = console.listen();
  try {
    return await _analyze(console, resolved, configuration, config, projectDir);
  } on Object catch (e, st) {
    console.write(
      describeFatalError(
        e,
        st,
        verbose: resolved.verbose,
        style: console.errStyle,
      ),
    );
    return 2;
  } finally {
    await logging.cancel();
    console.clearProgress();
  }
}

/// Everything after the options are read: analyze, report, remove.
Future<int> _analyze(
  Console console,
  ResolvedOptions resolved,
  CiachConfiguration configuration,
  ConfigFile config,
  String projectDir,
) async {
  describeConfigSource(config, projectDir: projectDir).forEach(_log.fine);

  final rootDir = Directory(resolved.rootPath);
  if (!rootDir.existsSync()) {
    console.error('Path does not exist: ${resolved.rootPath}');
    return 2;
  }

  if (resolved.force && !resolved.remove) {
    console.error(
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
    console.error(e.message);
    return 2;
  }

  // Built here so the checks below, --verbose and the run all read the same
  // normalized paths.
  final options = resolved.finderOptions(dartExecutable: dartExecutable);
  final rootPath = options.rootPath;

  if (options.analysisRootPath case final analysisRoot?) {
    if (!Directory(analysisRoot).existsSync()) {
      console.error('Analysis root does not exist: $analysisRoot');
      return 2;
    }
    // A root beside or below the scanned package would drop references, not
    // add them.
    if (!analysisRootContains(analysisRoot, rootPath)) {
      console.error(
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
      console.report('${Reporter.json(result)}\n');
    case 'github':
      // GitHub resolves annotation paths from the repo root, so prepend the
      // scan root's path from here.
      final prefix = p
          .split(p.relative(rootPath, from: Directory.current.path))
          .join('/');
      _log.fine("Prefixing annotation paths with '$prefix/'.");
      console.report(Reporter.github(result, pathPrefix: prefix));
    case _:
      console
        ..report('${Reporter.text(result, style: console.outStyle)}\n')
        // Warnings go to stderr so they never corrupt text stdout; the json
        // and github formats carry them in-band instead.
        ..write(Reporter.warningsText(result, style: console.errStyle))
        ..write(
          Reporter.problemsText(
            result,
            verbose: resolved.verbose,
            style: console.errStyle,
          ),
        );
  }

  if (result.unused.isNotEmpty && resolved.remove) {
    await _removeUnused(console, result, rootPath, resolved);
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
  Console console,
  FinderResult result,
  String rootPath,
  ResolvedOptions resolved,
) async {
  final style = console.outStyle;

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
    console.report(
      '${style.yellow('Nothing removed: all $blocked finding${blocked == 1 ? ' is' : 's are'} '
      'unsafe to auto-remove — remove them manually.')}\n',
    );
    return;
  }

  var proceed = resolved.force;
  if (!proceed) {
    _log.fine('Asking for confirmation; pass --force to skip the prompt.');
    // The chosen --format may not be human-readable; show the findings
    // again so the confirmation prompt is never a shot in the dark.
    if (resolved.format != 'text') {
      console.line(Reporter.text(result, style: console.errStyle));
    }
    if (!stdin.hasTerminal) {
      console.report(
        '${style.yellow('Refusing to remove declarations without a terminal to confirm on; pass --force to remove without asking.')}\n',
      );
      return;
    }
    console.report(
      style.bold('Remove $count unused declaration$plural? [y/N] '),
    );
    proceed = switch (stdin.readLineSync()?.trim().toLowerCase()) {
      'y' || 'yes' => true,
      _ => false,
    };
  }

  if (!proceed) {
    console.report('${style.hint('Skipped removal.')}\n');
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
  console.report(
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
    console.report('${style.bold('Note:')} $note\n');
  }
}
