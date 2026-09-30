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
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/cli/verbose.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/reporter.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.cli');

final _console = Console.standard();

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

Future<int> _run(List<String> arguments) async {
  final parser = buildParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    _log.severe('${e.message}\n\n${usage(parser)}');
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
      progressDefault: _console.errIsTerminal,
    );
  } on UsageException catch (e) {
    _log.severe(e.message);
    return 2;
  } on FormatException catch (e) {
    _log.severe(e.message);
    return 2;
  }

  _console.configure(
    color: resolved.color,
    progress: resolved.showProgress,
    verbose: resolved.verbose,
  );
  describeConfigSource(config, projectDir: projectDir).forEach(_log.config);

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
  ).forEach(_log.config);

  final result = await Ciach(options).run();
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

  switch (resolved.format) {
    case 'json':
      _console.output(Reporter.json(result));
    case 'github':
      // GitHub resolves annotation paths from the repo root, so prepend the
      // scan root's path from here.
      final prefix = p
          .split(p.relative(rootPath, from: Directory.current.path))
          .join('/');
      _log.config("Prefixing annotation paths with '$prefix/'.");
      _console.output(Reporter.github(result, pathPrefix: prefix));
    case _:
      _console.output(
        Reporter.text(
          result,
          style: _console.outStyle,
          verbose: resolved.verbose,
        ),
      );
  }

  if (result.unused.isNotEmpty && resolved.remove) {
    _removeUnused(result, rootPath, resolved);
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

/// Confirms (unless forced), removes the findings, and reports it.
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
  if (blocked > 0) {
    _log.fine(
      'Skipping $blocked of ${plural(result.unused.length, 'finding', 'findings')}: removing them safely would need a source rewrite (see --unused-union-members and remove safety).',
    );
  }
  if (count == 0) {
    _log.warning(
      blocked == 1
          ? 'Nothing removed: the finding is unsafe to auto-remove — remove '
                'it manually.'
          : 'Nothing removed: all $blocked findings are unsafe to auto-remove '
                '— remove them manually.',
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
    final proceed = _console.confirm(
      'Remove ${plural(count, 'unused declaration', 'unused declarations')}?',
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

  final removal = removeDeclarations(result.unused, rootPath);
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
