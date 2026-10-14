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
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';

/// Friendly `--kinds` names mapped to LSP symbol kinds.
const kindAliases = <String, SymbolKind>{
  'class': .class$,
  'mixin': .interface$,
  'interface': .interface$,
  'enum': .enum$,
  'extension': .namespace,
  'extension-type': .struct,
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

/// The accepted `--also` values: what is skipped by default, each a known
/// source of false positives.
const alsoNames = ['overrides', 'operators', 'tojson', 'union-members'];

/// Parses the `--also` values (comma-separated, repeatable).
///
/// Throws a [FormatException] naming the offending value on an unknown one,
/// which the command line would catch by itself, but a config file would not.
Set<String> parseAlso(List<String> raw) {
  final names = {
    for (final entry in raw)
      for (final name in entry.split(','))
        if (name.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
  };
  if (names.whereNot(alsoNames.contains).firstOrNull case final unknown?) {
    throw FormatException(
      "Unknown value '$unknown' for `also`. Valid values: ${alsoNames.join(', ')}.",
    );
  }
  return names;
}

/// What a removed option became: the values for the option with the config
/// key `key` to take. No values set it to an empty list.
typedef Replacement = ({String key, List<String> values});

/// The removed flags that became a value of `--also`, by config key.
const _alsoFlags = {
  'overrides': 'overrides',
  'operators': 'operators',
  'report-tojson': 'tojson',
  'unused-union-members': 'union-members',
};

/// The config keys of the options ciach no longer has.
const removedKeys = {
  'overrides',
  'operators',
  'report-tojson',
  'unused-union-members',
  'exported',
  'fail-public',
  'generated-suffix',
};

/// Why setting the removed option [key] to [value] (`true` or `false` for a
/// flag) is not needed any more, or what to use instead, in the config file
/// when [inConfig].
String removedOptionAdvice(
  String key,
  Object? value, {
  required bool inConfig,
}) {
  if (key == 'fail-public' && value == false) {
    return 'every finding counts toward the exit code, and what other packages can import is left out by default';
  }
  return switch (_replacementFor(key, value)) {
    null => 'that is the default now, so drop it',
    final replacement when inConfig =>
      'use `${replacement.key}: [${replacement.values.map(_quoted).join(', ')}]`',
    (:final key, values: []) => 'use `--$key=`',
    (:final key, :final values) =>
      'use ${values.map((value) => '`--$key ${_quoted(value)}`').join(' ')}',
  };
}

/// What setting the removed option [key] to [value] became, or `null` when
/// that is the default now.
Replacement? _replacementFor(String key, Object? value) => switch (key) {
  'exported' when value == true => (key: 'exported-packages', values: []),
  'generated-suffix' => (
    key: 'generated-glob',
    values: [
      for (final suffix in value is Iterable ? value : [value ?? '<suffix>'])
        '**/*$suffix',
    ],
  ),
  _ when value == true => _alsoFlags[key]?.let(
    (also) => (key: 'also', values: [also]),
  ),
  _ => null,
};

/// [value], single-quoted when a shell or YAML would read it otherwise.
String _quoted(String value) =>
    RegExp(r'^[\w.-]+$').hasMatch(value) ? value : "'$value'";

final _longOption = RegExp(r'^--(no-)?([\w-]+)(?:=(.*))?$');

/// Why the first removed option in [arguments] is gone and what to do
/// instead, or `null` when they name none.
String? removedOptionMessage(List<String> arguments) {
  for (final (i, argument) in arguments.indexed) {
    if (argument == '--') {
      break;
    }
    final match = _longOption.firstMatch(argument);
    final key = match?[2];
    if (match == null || key == null || !removedKeys.contains(key)) {
      continue;
    }
    final Object? value = switch (key) {
      // The value of `--generated-suffix` may be the next argument.
      'generated-suffix' => match[3] ?? arguments.elementAtOrNull(i + 1),
      _ => match[1] == null,
    };
    return '`${argument.split('=').first}` was removed: ${removedOptionAdvice(key, value, inConfig: false)}.';
  }
  return null;
}

/// The accepted `--format` values; the first one is the default, except on a
/// CI service with an annotation format, where it is that one.
const formatNames = [
  'text',
  'json',
  'github',
  'azure',
  'teamcity',
  'sarif',
  'checkstyle',
  'gitlab',
];

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
          'Report unused public declarations too. Disable to report only private (underscore-prefixed) declarations, which are the highest-confidence dead code.',
    ),
  ),
  exportedPackages(
    MultiStringOption.noSplit(
      group: _reportGroup,
      argName: 'exported-packages',
      configKey: '/exported-packages',
      defaultsTo: ['**'],
      valueHelp: 'glob',
      helpText:
          'Glob, relative to the root, of a package that code outside the analysis imports. What other packages can import from it is not reported. Defaults to every package; an empty value (--exported-packages=) checks the API of every package. Repeatable.',
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
      defaultsTo: false,
      helpText:
          'Also report declarations referenced only from other findings, and cycles of declarations that only reference each other. Off by default, because one false positive also flags everything only it referenced.',
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
      helpText: 'Glob(s), relative to the root, of files to skip. Repeatable.',
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
      helpText: 'If given, only scan files matching these glob(s). Repeatable.',
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
          "Glob, relative to the root, of files to treat as generated: their references count, but nothing in them is reported or edited, e.g. --generated-glob 'lib/l10n/**'. --exclude drops files entirely instead. Repeatable. Ignored when --generated is set.",
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
          'Exit with a non-zero status when any unused declaration, empty file or empty range is found. On by default in CI.',
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
          'Remove unused declarations and empty ranges from source, and delete empty files, after reporting them. Prompts for confirmation first, unless --force is also given.',
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

/// The full `--help` text, wrapping [parser]'s generated option list.
String usage(ArgParser parser) =>
    '''
ciach $ciachVersion

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

  `entry-points` lives only there: declarations a tool calls from generated
  code, each a `name` with an optional `glob` for the files it may live in.

    # $configFileName
    public: false
    exclude:
      - 'test/**'
    entry-points:
      - name: bootstrap               # an isolate entry point
        glob: 'lib/src/isolate.dart'
      - name: MyHost.callback         # a member, called from native code
        glob: 'lib/my_host.dart'
    kinds: [class, function]
    format: json

Ignore markers:
  A `// ciach:ignore` comment keeps the declaration on the next line, or the
  one named on its line when it trails code. `// ciach:ignore-start` and
  `// ciach:ignore-end` keep everything named between them, and
  `// ciach:ignore-file` keeps the whole file.

Examples:
  # Scan the current package
  ciach

  # Only private declarations, excluding tests, as JSON
  ciach --no-public -e 'test/**' -f json lib/

  # A monorepo package whose callers live in sibling packages
  ciach pkgs/core --analysis-root .

  # Read settings from a config file elsewhere
  ciach --config tool/ciach.yaml

  # Ignore the package's config file for one run
  ciach --no-config

  # In CI, --set-exit-if-changed and --verbose are on by default, and on GitHub
  # Actions each finding is an annotation; spelled out, the same works anywhere
  ciach -f github --set-exit-if-changed -v

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
