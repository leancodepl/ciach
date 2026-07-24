/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:collection/collection.dart';

/// Friendly `--kinds` names mapped to LSP symbol kinds.
const kindAliases = <String, SymbolKind>{
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

/// The `--kinds` alias names, sorted, for help text and error messages.
String get kindNames => kindAliases.keys.sorted().join(', ');

/// Parses the `--kinds` values (comma-separated, repeatable) into symbol kinds,
/// falling back to [FinderOptions.defaultKinds] when none are given.
///
/// Throws a [FormatException] naming the offending value on an unknown kind.
Set<SymbolKind> parseKinds(List<String> raw) {
  if (raw.isEmpty) {
    return FinderOptions.defaultKinds;
  }
  return {
    for (final entry in raw)
      for (final name in entry.split(','))
        if (name.trim().toLowerCase() case final trimmed
            when trimmed.isNotEmpty)
          kindAliases[trimmed] ??
              (throw FormatException(
                "Unknown kind '$trimmed'. Valid kinds: $kindNames.",
              )),
  };
}

/// Builds the CLI argument parser. Every flag and option ciach accepts is
/// declared here, so adding one is a single-file change.
ArgParser buildParser() => .new()
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
    'fail-public',
    defaultsTo: true,
    help:
        'Count unused public declarations toward the exit code (with\n'
        '--set-exit-if-changed). Use --no-fail-public to report them\n'
        'without failing the build.',
  )
  ..addFlag(
    'generated',
    help: 'Scan generated files (*.g.dart, *.freezed.dart, …). Off by default.',
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
    'unused-union-members',
    help:
        'Also flag a class whose only references are type patterns over its\n'
        '(sealed) supertype — matched but never constructed. Off by default:\n'
        'a `case Foo():` arm otherwise counts as a use. Report-only: these\n'
        'findings are surfaced but --remove never deletes them or their\n'
        'pattern arms (removing a sealed member and rewriting its switches\n'
        'is left to a human). Conservative: any reference that is not clearly\n'
        'a type pattern keeps the class alive.',
  )
  ..addFlag(
    'report-tojson',
    help:
        'Report a `toJson()` serialization hook as unused too. Off by\n'
        'default: `jsonEncode(obj)` calls `obj.toJson()` by dynamic dispatch\n'
        'with no source-level `.toJson()` reference for the search to see, so\n'
        'a live serializer would be flagged. Enable to audit dead `toJson`s.',
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
    'generated-suffix',
    help:
        'Additional filename suffix to treat as generated (and so\n'
        'exclude from the scan), on top of the built-in set (*.g.dart,\n'
        '*.freezed.dart, …). Use for custom code generators, e.g.\n'
        '--generated-suffix .gc.dart. Include the leading dot. Repeatable.\n'
        'Ignored when --generated is set.',
    valueHelp: 'suffix',
  )
  ..addMultiOption(
    'kinds',
    abbr: 'k',
    help:
        'Restrict to these declaration kinds (comma-separated).\n'
        'Valid: $kindNames.',
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

/// The full `--help` text, wrapping [parser]'s generated option list.
String usage(ArgParser parser) =>
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
