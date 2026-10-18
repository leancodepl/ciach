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
import 'package:ciach/src/cli/option_values.dart';
import 'package:config/config.dart';

/// The `entry-points` list of `{name, glob}` rules. It has no command-line
/// form; `ConfigFile` hands it over already parsed and validated.
final class EntryPointsOption extends ConfigOptionBase<List<EntryPoint>> {
  const EntryPointsOption({required super.configKey, super.helpText})
    : super(valueParser: const _EntryPointsParser(), defaultsTo: const []);
}

/// Never reached: the config layer supplies the parsed list, and there is no
/// string form to parse.
final class _EntryPointsParser extends ValueParser<List<EntryPoint>> {
  const _EntryPointsParser();

  @override
  List<EntryPoint> parse(String value) => throw const FormatException(
    'entry-points is a list of {name, glob} rules.',
  );
}

const _reportGroup = OptionGroup('What to report');
const _filesGroup = OptionGroup('Which files');
const _outputGroup = OptionGroup('Output');
const _ciGroup = OptionGroup('Exit code and removal');
const _serverGroup = OptionGroup('Analysis server');

/// Every setting ciach accepts, declared once for the command line, the config
/// file (`configKey`) and its default.
///
/// [help], [version], [config] and [noConfig] have no `configKey`: a config
/// file doesn't get to decide whether it is read, or what ciach is called.
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
  // No `-v`: that is --verbose.
  version(
    FlagOption(
      argName: 'version',
      negatable: false,
      defaultsTo: false,
      helpText: 'Print the ciach version and exit.',
    ),
  ),
  config(
    StringOption(
      argName: 'config',
      valueHelp: 'path',
      helpText:
          'Path to a YAML config file. Defaults to $configFileName in the analyzed package root, when present.',
    ),
  ),
  // A flag of its own, not a negated `config` — that name is the option above.
  noConfig(
    FlagOption(
      argName: 'no-config',
      negatable: false,
      defaultsTo: false,
      helpText:
          'Ignore any config file, including one that would be discovered automatically. Cannot be combined with --config.',
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
      group: _reportGroup,
      argName: 'public',
      configKey: '/public',
      defaultsTo: true,
      helpText:
          'Report unused public declarations too. Disable to report only private declarations, which are the highest-confidence dead code: those whose name starts with an underscore, and the members of unnamed extensions.',
    ),
  ),
  exportedPackages(
    MultiStringOption.noSplit(
      group: _reportGroup,
      argName: 'exported-packages',
      configKey: '/exported-packages',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText:
          'Glob, relative to the root, of a package that code outside the analysis imports, such as one published to pub.dev. What other packages can import from it is not reported. Repeatable.',
    ),
  ),
  unusedTranslations(
    FlagOption(
      group: _reportGroup,
      argName: 'unused-translations',
      configKey: '/unused-translations',
      defaultsTo: true,
      helpText:
          'Report the unused messages in the gen-l10n template file that an l10n.yaml configures. They are only reported, never removed: remove them from the template ARB file instead.',
    ),
  ),
  also(
    MultiStringOption(
      group: _reportGroup,
      argName: 'also',
      configKey: '/also',
      defaultsTo: [],
      valueHelp: 'category,category',
      allowedValues: alsoNames,
      customValidator: parseAlso,
      helpText:
          'Also report what is skipped by default because a reference search misses some of its uses, so it brings false positives. A comma-separated list of:',
      allowedHelp: {
        'overrides':
            '@override members, often reached polymorphically or by a framework.',
        'operators':
            'Operator overloads: the analysis server never resolves `a + b` to the operator, so a used one is reported every time.',
        'tojson':
            'toJson() hooks, which `jsonEncode(obj)` calls by dynamic dispatch.',
        'union-members':
            'Classes matched only by type patterns over their sealed supertype, never constructed. Report-only: --remove never deletes them or their pattern arms.',
      },
    ),
  ),
  transitive(
    FlagOption(
      group: _reportGroup,
      argName: 'transitive',
      configKey: '/transitive',
      defaultsTo: true,
      helpText:
          'Also report declarations referenced only from other findings, and cycles of declarations that only reference each other, each naming what it is only referenced from. Disable to report only what nothing references at all.',
    ),
  ),
  exclude(
    MultiStringOption.noSplit(
      group: _filesGroup,
      argName: 'exclude',
      argAbbrev: 'e',
      configKey: '/exclude',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText:
          'Glob, relative to the root, of files to skip: nothing in them is reported, but their references still count. Repeatable.',
    ),
  ),
  include(
    MultiStringOption.noSplit(
      group: _filesGroup,
      argName: 'include',
      argAbbrev: 'i',
      configKey: '/include',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText:
          'Glob, relative to the root, of files to scan. When this option is given, other files are skipped, but their references still count. Repeatable.',
    ),
  ),
  generatedGlob(
    MultiStringOption.noSplit(
      group: _filesGroup,
      argName: 'generated-glob',
      configKey: '/generated-glob',
      defaultsTo: [],
      valueHelp: 'glob',
      helpText:
          "Glob, relative to the root, of files to treat as generated: their references count, but nothing in them is reported or edited, e.g. --generated-glob 'lib/l10n/**'. Repeatable. Ignored when --generated is set.",
    ),
  ),
  analysisRoot(
    StringOption(
      group: _filesGroup,
      argName: 'analysis-root',
      configKey: '/analysis-root',
      valueHelp: 'path',
      helpText:
          'Count references from this whole directory, not just the scanned package — for a monorepo where sibling packages depend on it by `path:`. Must contain the scanned path; what is scanned, reported and removed is unchanged. A pub workspace needs no setting.',
    ),
  ),
  generated(
    FlagOption(
      group: _filesGroup,
      argName: 'generated',
      configKey: '/generated',
      defaultsTo: false,
      helpText:
          'Scan generated files (*.g.dart, *.freezed.dart, …). Off by default.',
    ),
  ),
  projectConfig(
    FlagOption(
      group: _filesGroup,
      argName: 'project-config',
      configKey: '/project-config',
      defaultsTo: true,
      helpText:
          'Read entry points and generated files from pubspec.yaml, build.yaml and l10n.yaml.',
    ),
  ),
  // Config file only: a map has no command-line spelling.
  entryPoints(
    EntryPointsOption(
      configKey: '/entry-points',
      helpText:
          'Declarations a tool calls from generated code, so never reported: rules with a `name` (`bootstrap`, `MyHost.callback`) and an optional `glob` (one, or a list) for the files. Built in: `main`, and `testExecutable` in a flutter_test_config.dart.',
    ),
  ),
  kinds(
    MultiStringOption(
      group: _reportGroup,
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
          'Restrict to these declaration kinds (comma-separated). The kinds are listed at the end of this help.',
    ),
  ),
  setExitIfChanged(
    FlagOption(
      group: _ciGroup,
      argName: 'set-exit-if-changed',
      configKey: '/set-exit-if-changed',
      helpText:
          'Exit with a non-zero status when any unused declaration or empty file is found. On by default in CI.',
    ),
  ),
  ci(
    FlagOption(
      group: _ciGroup,
      argName: 'ci',
      configKey: '/ci',
      helpText:
          'Assume CI: --set-exit-if-changed and --verbose default to on, progress to off, and --format to annotations on GitHub Actions, Azure Pipelines and TeamCity. Detected from CI, GITHUB_ACTIONS and the like; explicit options still win.',
    ),
  ),
  remove(
    FlagOption(
      group: _ciGroup,
      argName: 'remove',
      configKey: '/remove',
      negatable: false,
      defaultsTo: false,
      helpText:
          'Remove unused declarations from source, and delete empty files, after reporting them. Prompts for confirmation first, unless --force is also given.',
    ),
  ),
  force(
    FlagOption(
      group: _ciGroup,
      argName: 'force',
      configKey: '/force',
      negatable: false,
      defaultsTo: false,
      helpText: 'Skip the confirmation prompt for --remove. Requires --remove.',
    ),
  ),
  format(
    StringOption(
      group: _outputGroup,
      argName: 'format',
      argAbbrev: 'f',
      configKey: '/format',
      allowedValues: formatNames,
      helpText:
          'Output format. Defaults to github, azure or teamcity on that CI service, text elsewhere.',
      allowedHelp: {
        'text': 'Human-readable, grouped by file.',
        'json': 'Machine-readable JSON.',
        'github': 'GitHub Actions `::warning` annotations.',
        'azure': 'Azure Pipelines `##vso[task.logissue]` warnings.',
        'teamcity': 'TeamCity `##teamcity[inspection]` service messages.',
        'sarif': 'SARIF 2.1.0, for GitHub code scanning and other dashboards.',
        'checkstyle': 'Checkstyle XML, for Jenkins and other report plugins.',
        'gitlab': 'GitLab Code Quality JSON, for a `codequality` artifact.',
      },
    ),
  ),
  color(
    FlagOption(
      group: _outputGroup,
      argName: 'color',
      configKey: '/color',
      helpText:
          'Colorize the output. Defaults to auto-detection per stream; honors NO_COLOR.',
    ),
  ),
  progress(
    FlagOption(
      group: _outputGroup,
      argName: 'progress',
      configKey: '/progress',
      helpText: 'Show scan progress on stderr. Defaults to on for a terminal.',
    ),
  ),
  verbose(
    FlagOption(
      group: _outputGroup,
      argName: 'verbose',
      argAbbrev: 'v',
      configKey: '/verbose',
      helpText:
          'Explain what is happening on stderr: the config file and what it set, the resolved settings, each scan phase, and what --remove touches. Supersedes --progress. On by default in CI.',
    ),
  ),
  concurrency(
    IntOption(
      group: _serverGroup,
      argName: 'concurrency',
      argAbbrev: 'j',
      configKey: '/concurrency',
      valueHelp: 'n',
      defaultsTo: 16,
      min: 1,
      helpText:
          'How many reference queries to run against the analysis server at once. Higher can be faster on large projects, up to the limit of the analysis server parallelism.',
    ),
  ),
  dart(
    StringOption(
      group: _serverGroup,
      argName: 'dart',
      configKey: '/dart',
      valueHelp: 'path',
      helpText:
          'Path to the dart executable used to launch the analysis server. Defaults to the SDK running this tool.',
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
  final parser = ArgParser(usageLineLength: 100);
  prepareOptionsForParsing(CiachOption.values, parser);
  return parser;
}
