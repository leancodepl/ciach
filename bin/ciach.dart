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
import 'package:ciach/src/reporter.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  // Returning an int from `main` does not set the process exit code in Dart,
  // so route the result through the global `exitCode`.
  exitCode = await _run(arguments);
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

  final rest = args.rest;
  if (rest.length > 1) {
    stderr.writeln(
      'Expected at most one path argument, got: ${rest.join(', ')}',
    );
    return 2;
  }
  final rootPath = rest.isEmpty ? '.' : rest.first;
  final rootDir = Directory(rootPath);
  if (!rootDir.existsSync()) {
    stderr.writeln('Path does not exist: $rootPath');
    return 2;
  }

  if (args.flag('force') && !args.flag('remove')) {
    stderr.writeln('--force requires --remove.');
    return 2;
  }

  final Set<SymbolKind> kinds;
  try {
    kinds = parseKinds(args.multiOption('kinds'));
  } on FormatException catch (e) {
    stderr.writeln(e.message);
    return 2;
  }

  // `allowed` on the option already rejects unknown values during parsing.
  final format = args.option('format')!;

  final useColor = args.wasParsed('color')
      ? args.flag('color')
      : stdout.supportsAnsiEscapes;
  // Progress goes to stderr; default on only when it won't clutter a pipe.
  final showProgress = args.wasParsed('progress')
      ? args.flag('progress')
      : stderr.hasTerminal;

  final int concurrency;
  try {
    concurrency = int.parse(args.option('concurrency')!);
    if (concurrency < 1) {
      throw const FormatException();
    }
  } on FormatException {
    stderr.writeln('--concurrency must be a positive integer.');
    return 2;
  }

  final options = FinderOptions(
    rootPath: rootDir.absolute.path,
    includeGlobs: args.multiOption('include'),
    excludeGlobs: args.multiOption('exclude'),
    kinds: kinds,
    includePublic: args.flag('public'),
    includeGenerated: args.flag('generated'),
    additionalGeneratedSuffixes: args.multiOption('generated-suffix'),
    skipOverrides: !args.flag('overrides'),
    skipOperators: !args.flag('operators'),
    unusedUnionMembers: args.flag('unused-union-members'),
    reportToJson: args.flag('report-tojson'),
    concurrency: concurrency,
    dartExecutable: args.option('dart'),
    onProgress: showProgress ? _ProgressPrinter().update : null,
  );

  final FinderResult result;
  try {
    result = await Ciach(options).run();
  } on Object catch (e, st) {
    if (showProgress) {
      stderr.writeln();
    }
    stderr
      ..writeln('Failed to analyze: $e')
      ..writeln(st);
    return 2;
  }

  if (showProgress) {
    stderr.writeln();
  }

  switch (format) {
    case 'json':
      stdout.writeln(Reporter.json(result));
    case 'github':
      // GitHub resolves annotation paths from the repo root; make the finding
      // paths root-relative by prepending the scan root's path from here.
      final prefix = p
          .split(
            p.relative(rootDir.absolute.path, from: Directory.current.path),
          )
          .join('/');
      stdout.write(Reporter.github(result, pathPrefix: prefix));
    case _:
      stdout.writeln(Reporter.text(result, useColor: useColor));
  }

  if (result.unused.isNotEmpty && args.flag('remove')) {
    await _removeUnused(result, rootDir.absolute.path, args, format, useColor);
  }

  if (args.flag('set-exit-if-changed')) {
    // Public findings are still reported above; --no-fail-public only keeps
    // them out of the exit code, so the build fails on private findings alone.
    final failing = args.flag('fail-public')
        ? result.unused
        : result.unused.where((d) => d.isPrivate);
    if (failing.isNotEmpty) {
      return 1;
    }
  }
  return 0;
}

/// Reports what would be removed, confirms unless [ArgResults.flag]
/// `'force'` is set, and deletes the unused declarations from disk.
Future<void> _removeUnused(
  FinderResult result,
  String rootPath,
  ArgResults args,
  String format,
  bool useColor,
) async {
  final count = result.unused.length;
  final plural = count == 1 ? '' : 's';

  var proceed = args.flag('force');
  if (!proceed) {
    // The chosen --format may not be human-readable; show the findings
    // again so the confirmation prompt is never a shot in the dark.
    if (format != 'text') {
      stderr.writeln(Reporter.text(result, useColor: useColor));
    }
    if (!stdin.hasTerminal) {
      stdout.writeln(
        'Refusing to remove declarations without a terminal to confirm on; '
        'pass --force to remove without asking.',
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

  final filesChanged = removeDeclarations(result.unused, rootPath);
  stdout.writeln(
    'Removed $count unused declaration$plural from $filesChanged '
    "file${filesChanged == 1 ? '' : 's'}. Run 'dart format' to tidy up spacing.",
  );
  // Surface any advisory hints (e.g. a removed prevent-instantiation
  // constructor) once more, since removing the declaration also removes the
  // reported line that carried the hint.
  final removedHints = result.unused
      .where((d) => !d.removalBlocked && d.hint != null)
      .map((d) => '${d.qualifiedName}: ${d.hint}')
      .toSet();
  for (final note in removedHints) {
    stdout.writeln('Note: $note');
  }
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
