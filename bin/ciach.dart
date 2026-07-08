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
import 'package:ciach/src/reporter.dart';
import 'package:path/path.dart' as p;

/// Friendly `--kinds` names mapped to LSP symbol kinds.
const _kindAliases = <String, SymbolKind>{
  'class': .class$,
  'mixin': .interface$,
  'interface': .interface$,
  'enum': .enum$,
  'extension': .struct,
  'function': .function,
  'method': .method,
  'constructor': .constructor,
  'field': .field,
  'property': .property,
  'getter': .property,
  'setter': .property,
  'variable': .variable,
  'constant': .constant,
  'enum-value': .enumMember,
};

Future<void> main(List<String> arguments) async {
  // Returning an int from `main` does not set the process exit code in Dart,
  // so route the result through the global `exitCode`.
  exitCode = await _run(arguments);
}

Future<int> _run(List<String> arguments) async {
  final parser = _buildParser();

  final ArgResults args;
  try {
    args = parser.parse(arguments);
  } on FormatException catch (e) {
    stderr
      ..writeln(e.message)
      ..writeln()
      ..writeln(_usage(parser));
    return 2;
  }

  if (args.flag('help')) {
    stdout.writeln(_usage(parser));
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
    kinds = _parseKinds(args.multiOption('kinds'));
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
    skipOverrides: !args.flag('overrides'),
    skipOperators: !args.flag('operators'),
    ignoreDocReferences: args.flag('ignore-doc-references'),
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

  if (result.unused.isNotEmpty && args.flag('set-exit-if-changed')) {
    return 1;
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
    final answer = stdin.readLineSync()?.trim().toLowerCase();
    proceed = answer == 'y' || answer == 'yes';
  }

  if (!proceed) {
    stdout.writeln('Skipped removal.');
    return;
  }

  final filesChanged = removeDeclarations(result.unused, rootPath);
  stdout.writeln(
    'Removed $count unused declaration$plural from $filesChanged '
    'file${filesChanged == 1 ? '' : 's'}. '
    "Run 'dart format' to tidy up spacing.",
  );
}

Set<SymbolKind> _parseKinds(List<String> raw) {
  if (raw.isEmpty) {
    return FinderOptions.defaultKinds;
  }
  final kinds = <SymbolKind>{};
  for (final entry in raw) {
    for (final name in entry.split(',')) {
      final trimmed = name.trim().toLowerCase();
      if (trimmed.isEmpty) {
        continue;
      }
      final kind = _kindAliases[trimmed];
      if (kind == null) {
        throw FormatException(
          "Unknown kind '$trimmed'. Valid kinds: "
          '${(_kindAliases.keys.toList()..sort()).join(', ')}.',
        );
      }
      kinds.add(kind);
    }
  }
  return kinds;
}

ArgParser _buildParser() {
  return .new()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Print this usage information.',
    )
    ..addFlag(
      'public',
      defaultsTo: true,
      help:
          'Report unused public declarations too. Disable to report only\n'
          'private (underscore-prefixed) declarations, which are the\n'
          'highest-confidence dead code.',
    )
    ..addFlag(
      'generated',
      help:
          'Scan generated files (*.g.dart, *.freezed.dart, …). Off by default.',
    )
    ..addFlag(
      'overrides',
      help:
          'Report members annotated with @override too. Off by default,\n'
          'since overrides are often reached polymorphically and a plain\n'
          'reference search can miss those uses.',
    )
    ..addFlag(
      'operators',
      help:
          'Report operator overloads (operator +, operator ==, …) too. Off\n'
          'by default: the analysis server never resolves infix operator\n'
          "syntax (a + b) back to the operator's declaration, so a used\n"
          'operator is reported as unused every time.',
    )
    ..addFlag(
      'ignore-doc-references',
      help:
          "Don't count dartdoc [Xxx] comment links as a use. Off by\n"
          'default: such a link resolves to a real declaration, so\n'
          'treating it as unused risks flagging something that really is\n'
          'referenced, just only from documentation.',
    )
    ..addFlag(
      'set-exit-if-changed',
      help:
          'Exit with a non-zero status when any unused declaration is found\n'
          '(useful in CI).',
    )
    ..addFlag(
      'remove',
      help:
          'Remove unused declarations from source after reporting them.\n'
          'Prompts for confirmation first, unless --force is also given.',
    )
    ..addFlag(
      'force',
      help: 'Skip the confirmation prompt for --remove. Requires --remove.',
    )
    ..addMultiOption(
      'exclude',
      abbr: 'e',
      help: 'Glob(s), relative to the root, of files to skip. Repeatable.',
      valueHelp: 'glob',
    )
    ..addMultiOption(
      'include',
      abbr: 'i',
      help: 'If given, only scan files matching these glob(s). Repeatable.',
      valueHelp: 'glob',
    )
    ..addMultiOption(
      'kinds',
      abbr: 'k',
      help:
          'Restrict to these declaration kinds (comma-separated).\n'
          'Valid: ${(_kindAliases.keys.toList()..sort()).join(', ')}.',
      valueHelp: 'kind,kind',
    )
    ..addOption(
      'format',
      abbr: 'f',
      allowed: ['text', 'json', 'github'],
      defaultsTo: 'text',
      help: 'Output format.',
      allowedHelp: {
        'text': 'Human-readable, grouped by file.',
        'json': 'Machine-readable JSON.',
        'github': 'GitHub Actions `::warning` annotations.',
      },
    )
    ..addFlag(
      'color',
      help: 'Colorize text output. Defaults to auto-detecting the terminal.',
    )
    ..addFlag(
      'progress',
      help: 'Show scan progress on stderr. Defaults to on for a terminal.',
    )
    ..addOption(
      'concurrency',
      abbr: 'j',
      defaultsTo: '16',
      help:
          'How many reference queries to run against the analysis server at\n'
          'once. Higher can be faster on large projects, up to the limit of\n'
          'the analysis server parallelism.',
      valueHelp: 'n',
    )
    ..addOption(
      'dart',
      help:
          'Path to the dart executable used to launch the analysis server.\n'
          'Defaults to the SDK running this tool.',
      valueHelp: 'path',
    );
}

String _usage(ArgParser parser) =>
    '''
Find unused (never-referenced) declarations in a Dart/Flutter package.

Usage: ciach [options] [path]

  path   Package root to analyze (defaults to the current directory).

${parser.usage}

Examples:
  # Scan the current package
  ciach

  # Only private declarations, excluding tests, as JSON
  ciach --no-public -e 'test/**' -f json lib/

  # GitHub Actions annotations, fail the job if anything is found
  ciach -f github --set-exit-if-changed

  # Remove what's found, after confirming
  ciach --remove

  # Remove without asking (e.g. in a script)
  ciach --remove --force''';

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
