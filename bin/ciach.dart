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
import 'package:ciach/src/cli/ci.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/console.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/report.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reporter.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';

final _log = Logger('ciach.cli');

final _console = Console.standard();

/// The CI service the environment says this run is on, if any.
final _detectedCi = CiRunner.detect(Platform.environment);

Future<void> main(List<String> arguments) async {
  final logging = _console.attach();
  try {
    exitCode = await _run(arguments);
  } on Object catch (e, st) {
    _log.severe('ciach stopped.', e, st);
    exitCode = 2;
  } finally {
    await logging.cancel();
    _console.clearProgress();
  }
}

/// [arguments] parsed by [parser], or `null` after logging why they don't
/// parse: a removed option is named with what replaced it, anything else comes
/// with the usage.
ArgResults? _parse(ArgParser parser, List<String> arguments) {
  if (removedOptionMessage(arguments) case final message?) {
    _log.severe(message);
    return null;
  }
  try {
    return parser.parse(arguments);
  } on FormatException catch (e) {
    _log.severe('''
${e.message}

${usage(parser)}''');
    return null;
  }
}

Future<int> _run(List<String> arguments) async {
  final parser = buildParser();

  final args = _parse(parser, arguments);
  if (args == null) {
    return 2;
  }

  if (args.flag('help')) {
    _console.output(usage(parser));
    return 0;
  }

  if (args.flag('version')) {
    _console.output('ciach $ciachVersion');
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

  final loaded = _loadOptions(
    args,
    projectDir: projectDir,
    explicitConfig: explicitConfig,
    ignoreConfig: ignoreConfig,
  );
  if (loaded == null) {
    return 2;
  }
  final (:config, :configuration, :resolved) = loaded;

  _console.configure(
    color: resolved.color,
    progress: resolved.showProgress,
    verbose: resolved.verbose,
  );
  describeConfigSource(config, projectDir: projectDir).forEach(_log.config);
  describeCi(resolved, detected: _detectedCi).forEach(_log.config);

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

  if (!_analysisRootIsValid(options)) {
    return 2;
  }

  describeSettings(
    configuration,
    resolved,
    options,
    dartExecutable: dartExecutable,
  ).forEach(_log.config);

  final result = await Ciach(options).run();
  logSummary(result);

  writeReport(_console, result, resolved, rootPath);

  if (result.hasFindings && resolved.remove) {
    _removeUnused(result, rootPath, resolved);
  } else if (result.hasFindings) {
    _log.fine('Leaving the findings in place; --remove was not given.');
  }

  return exitCodeFor(result, resolved);
}

/// Confirms (unless forced), removes the findings and empty files, and reports
/// it.
void _removeUnused(
  FinderResult result,
  String rootPath,
  ResolvedOptions resolved,
) {
  // Report-only findings are left in place, so counting them would promise an
  // edit that never happens.
  final removable = result.unused.whereNot((d) => d.removalBlocked).toList();
  final count = removable.length;
  final blocked = result.unused.length - count;
  final emptyCount = result.emptyFiles.length;
  if (blocked > 0) {
    _log.fine(
      'Skipping $blocked of ${plural(result.unused.length, 'finding', 'findings')}: removing them safely would need a source rewrite (see --also union-members and remove safety).',
    );
  }
  if (count == 0 && emptyCount == 0) {
    _log.warning(
      blocked == 1
          ? 'Nothing removed: the finding is unsafe to auto-remove — remove it manually.'
          : 'Nothing removed: all $blocked findings are unsafe to auto-remove — remove them manually.',
    );
    return;
  }

  if (!resolved.force) {
    if (!_console.interactive) {
      _log.warning(
        'Refusing to remove declarations without a terminal to confirm on; pass --force to remove without asking.',
      );
      return;
    }
    _log.fine('Asking for confirmation; pass --force to skip the prompt.');
    final what = [
      if (count > 0) plural(count, 'unused declaration', 'unused declarations'),
      if (emptyCount > 0) plural(emptyCount, 'empty file', 'empty files'),
    ].join(' and ');
    final proceed = _console.confirm(
      'Remove $what?',
      // Non-text formats aren't readable, so show the findings first.
      preamble: resolved.format == 'text'
          ? null
          : Reporter.text(result, style: _console.errStyle),
    );
    if (!proceed) {
      _console.output(Reporter.removal(null, style: _console.outStyle));
      return;
    }
  }

  final removal = removeDeclarations(
    result.unused,
    rootPath,
    emptyFiles: result.emptyFiles,
  );
  _console.output(
    Reporter.removal(
      removal,
      removed: count,
      blocked: blocked,
      notes: {
        for (final d in removable)
          if (d.hint case final hint?) '${d.qualifiedName}: $hint',
      },
      style: _console.outStyle,
    ),
  );
}

bool _analysisRootIsValid(FinderOptions options) {
  final rootPath = options.rootPath;
  if (options.analysisRootPath case final analysisRoot?) {
    if (!Directory(analysisRoot).existsSync()) {
      _log.severe('Analysis root does not exist: $analysisRoot');
      return false;
    }
    // A root beside or below the scanned package would drop references, not
    // add them.
    if (!analysisRootContains(analysisRoot, rootPath)) {
      _log.severe(
        'The analysis root must contain the analyzed path: $analysisRoot does not contain $rootPath.',
      );
      return false;
    }
  }
  return true;
}

/// The options [args] resolve to with the config file, or `null` once it has
/// logged why they don't.
({
  ConfigFile config,
  CiachConfiguration configuration,
  ResolvedOptions resolved,
})?
_loadOptions(
  ArgResults args, {
  required String projectDir,
  required String? explicitConfig,
  required bool ignoreConfig,
}) {
  try {
    final ConfigFile config = .load(
      projectDir: projectDir,
      explicitPath: explicitConfig,
      ignore: ignoreConfig,
    );
    final configuration = resolveConfiguration(args, config);
    final resolved = resolveOptions(
      configuration,
      // Progress goes to stderr, so default it on only for a terminal.
      progressDefault: _console.errIsTerminal,
      detectedCi: _detectedCi,
    );
    return (config: config, configuration: configuration, resolved: resolved);
  } on UsageException catch (e) {
    _log.severe(e.message);
    return null;
  } on FormatException catch (e) {
    _log.severe(e.message);
    return null;
  }
}
