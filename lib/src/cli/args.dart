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
import 'package:config/config.dart';

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

/// The accepted `--format` values; the first one is the default.
const formatNames = ['text', 'json', 'github'];

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

/// Every setting ciach accepts, declared once for the command line, the config
/// file (`configKey`) and its default.
///
/// [help], [config] and [noConfig] have no `configKey`: a config file doesn't
/// get to decide whether it is read.
enum CiachOption<V> implements OptionDefinition<V> {
  help(
    FlagOption(
      argName: 'help',
      argAbbrev: 'h',
      negatable: false,
      defaultsTo: false,
      helpText: 'Print this usage information.',
    ),
  ),
  config(
    StringOption(
      argName: 'config',
      valueHelp: 'path',
      helpText:
          'Path to a YAML config file. Defaults to $configFileName in the\n'
          'analyzed package root, when present.',
    ),
  ),
  // A flag of its own, not a negated `config` — that name is the option above.
  noConfig(
    FlagOption(
      argName: 'no-config',
      negatable: false,
      defaultsTo: false,
      helpText:
          'Ignore any config file, including one that would be discovered\n'
          'automatically. Cannot be combined with --config.',
    ),
  ),
  path(
    StringOption(
      argPos: 0,
      configKey: '/path',
      defaultsTo: '.',
      helpText: 'Package root to analyze.',
    ),
  ),
  public(
    FlagOption(
      argName: 'public',
      configKey: '/public',
      defaultsTo: true,
      helpText:
          'Report unused public declarations too. Disable to report only\n'
          'private (underscore-prefixed) declarations, which are the\n'
          'highest-confidence dead code.',
    ),
  ),
  generated(
    FlagOption(
      argName: 'generated',
      configKey: '/generated',
      defaultsTo: false,
      helpText:
          'Scan generated files (*.g.dart, *.freezed.dart, …). Off by default.',
    ),
  ),
  overrides(
    FlagOption(
      argName: 'overrides',
      configKey: '/overrides',
      defaultsTo: false,
      helpText:
          'Report members annotated with @override too. Off by default,\n'
          'since overrides are often reached polymorphically and a plain\n'
          'reference search can miss those uses.',
    ),
  ),
  operators(
    FlagOption(
      argName: 'operators',
      configKey: '/operators',
      defaultsTo: false,
      helpText:
          'Report operator overloads (operator +, operator ==, …) too. Off\n'
          'by default: the analysis server never resolves infix operator\n'
          "syntax (a + b) back to the operator's declaration, so a used\n"
          'operator is reported as unused every time.',
    ),
  ),
  unusedUnionMembers(
    FlagOption(
      argName: 'unused-union-members',
      configKey: '/unused-union-members',
      defaultsTo: false,
      helpText:
          'Also flag a class whose only references are type patterns over its\n'
          '(sealed) supertype — matched but never constructed. Off by default:\n'
          'a `case Foo():` arm otherwise counts as a use. Report-only: these\n'
          'findings are surfaced but --remove never deletes them or their\n'
          'pattern arms (removing a sealed member and rewriting its switches\n'
          'is left to a human). Conservative: any reference that is not clearly\n'
          'a type pattern keeps the class alive.',
    ),
  ),
  reportToJson(
    FlagOption(
      argName: 'report-tojson',
      configKey: '/report-tojson',
      defaultsTo: false,
      helpText:
          'Report a `toJson()` serialization hook as unused too. Off by\n'
          'default: `jsonEncode(obj)` calls `obj.toJson()` by dynamic dispatch\n'
          'with no source-level `.toJson()` reference for the search to see, so\n'
          'a live serializer would be flagged. Enable to audit dead `toJson`s.',
    ),
  ),
  setExitIfChanged(
    FlagOption(
      argName: 'set-exit-if-changed',
      configKey: '/set-exit-if-changed',
      negatable: false,
      defaultsTo: false,
      helpText:
          'Exit with a non-zero status when any unused declaration is found\n'
          '(useful in CI).',
    ),
  ),
  remove(
    FlagOption(
      argName: 'remove',
      configKey: '/remove',
      negatable: false,
      defaultsTo: false,
      helpText:
          'Remove unused declarations from source after reporting them.\n'
          'Prompts for confirmation first, unless --force is also given.',
    ),
  ),
  force(
    FlagOption(
      argName: 'force',
      configKey: '/force',
      negatable: false,
      defaultsTo: false,
      helpText: 'Skip the confirmation prompt for --remove. Requires --remove.',
    ),
  ),
  exclude(
    MultiStringOption.noSplit(
      argName: 'exclude',
      argAbbrev: 'e',
      configKey: '/exclude',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText: 'Glob(s), relative to the root, of files to skip. Repeatable.',
    ),
  ),
  include(
    MultiStringOption.noSplit(
      argName: 'include',
      argAbbrev: 'i',
      configKey: '/include',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText: 'If given, only scan files matching these glob(s). Repeatable.',
    ),
  ),
  generatedSuffix(
    MultiStringOption.noSplit(
      argName: 'generated-suffix',
      configKey: '/generated-suffix',
      defaultsTo: [],
      valueHelp: 'suffix',
      helpText:
          'Additional filename suffix to treat as generated (and so\n'
          'exclude from the scan), on top of the built-in set (*.g.dart,\n'
          '*.freezed.dart, …). Use for custom code generators, e.g.\n'
          '--generated-suffix .gc.dart. Include the leading dot. Repeatable.\n'
          'Ignored when --generated is set.',
    ),
  ),
  kinds(
    MultiStringOption(
      argName: 'kinds',
      argAbbrev: 'k',
      configKey: '/kinds',
      defaultsTo: [],
      valueHelp: 'kind,kind',
      // Rejects an unknown kind wherever it came from; the conversion to
      // symbol kinds happens later.
      customValidator: parseKinds,
      // Listed in `usage`, which can read them off kindAliases.
      helpText:
          'Restrict to these declaration kinds (comma-separated).\n'
          'The kinds are listed at the end of this help.',
    ),
  ),
  format(
    StringOption(
      argName: 'format',
      argAbbrev: 'f',
      configKey: '/format',
      allowedValues: formatNames,
      defaultsTo: 'text',
      helpText: 'Output format.',
      allowedHelp: {
        'text': 'Human-readable, grouped by file.',
        'json': 'Machine-readable JSON.',
        'github': 'GitHub Actions `::warning` annotations.',
      },
    ),
  ),
  color(
    FlagOption(
      argName: 'color',
      configKey: '/color',
      helpText:
          'Colorize text output. Defaults to auto-detecting the terminal.',
    ),
  ),
  progress(
    FlagOption(
      argName: 'progress',
      configKey: '/progress',
      helpText: 'Show scan progress on stderr. Defaults to on for a terminal.',
    ),
  ),
  verbose(
    FlagOption(
      argName: 'verbose',
      argAbbrev: 'v',
      configKey: '/verbose',
      defaultsTo: false,
      helpText:
          'Explain what is happening on stderr: which config file was used and\n'
          'what it set, the settings the run ended up with, each scan phase as\n'
          'it starts, and what --remove touches. Supersedes --progress, whose\n'
          'single overwriting line would fight with it.',
    ),
  ),
  concurrency(
    IntOption(
      argName: 'concurrency',
      argAbbrev: 'j',
      configKey: '/concurrency',
      valueHelp: 'n',
      defaultsTo: 16,
      min: 1,
      helpText:
          'How many reference queries to run against the analysis server at\n'
          'once. Higher can be faster on large projects, up to the limit of\n'
          'the analysis server parallelism.',
    ),
  ),
  dart(
    StringOption(
      argName: 'dart',
      configKey: '/dart',
      valueHelp: 'path',
      helpText:
          'Path to the dart executable used to launch the analysis server.\n'
          'Defaults to the SDK running this tool.',
    ),
  );

  const CiachOption(this.option);

  @override
  final ConfigOptionBase<V> option;

  /// The `ciach.yaml` key for this option, its JSON pointer without the `/`.
  String? get configKey => option.configKey?.substring(1);
}

/// Ciach's resolved options, named so the enum's `dynamic` argument is written
/// once.
typedef CiachConfiguration = Configuration<CiachOption<dynamic>>;

/// The file name config discovery looks for in the project directory.
const configFileName = 'ciach.yaml';

/// The argument parser for [CiachOption.values].
ArgParser buildParser() {
  final parser = ArgParser();
  prepareOptionsForParsing(CiachOption.values, parser);
  return parser;
}

/// The full `--help` text, wrapping [parser]'s generated option list.
String usage(ArgParser parser) =>
    '''
Find unused (never-referenced) declarations in a Dart/Flutter package.

Usage: ciach [options] [path]

  path   Package root to analyze (defaults to the current directory).

${parser.usage}

Declaration kinds (-k, --kinds):
${_wrapped(kindNames, indent: '  ')}

Config file:
  Every option above can also be set in $configFileName in the package root,
  keyed by its long name, plus `path` for the positional argument. The command
  line wins over the file; --no-config ignores the file; --verbose says which
  file was read and what it set.

    # $configFileName
    public: false
    exclude:
      - 'test/**'
    kinds: [class, function]
    format: json

Examples:
  # Scan the current package
  ciach

  # Only private declarations, excluding tests, as JSON
  ciach --no-public -e 'test/**' -f json lib/

  # Read settings from a config file elsewhere
  ciach --config tool/ciach.yaml

  # Ignore the package's config file for one run
  ciach --no-config

  # GitHub Actions annotations, fail the job if anything is found
  ciach -f github --set-exit-if-changed

  # Remove what's found, after confirming
  ciach --remove

  # Remove without asking (e.g. in a script)
  ciach --remove --force''';

/// [text] as [indent]-prefixed lines of at most [width] characters.
String _wrapped(String text, {String indent = '', int width = 76}) {
  final lines = <String>[];
  for (final word in text.split(' ')) {
    if (lines.isEmpty || '${lines.last} $word'.length > width) {
      lines.add('$indent$word');
    } else {
      lines[lines.length - 1] = '${lines.last} $word';
    }
  }
  return lines.join('\n');
}
