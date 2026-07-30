import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/models.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

/// The `--verbose` account of where the run's settings came from: the config
/// file that was read (and what it set), skipped, or looked for in vain.
///
/// [projectDir] is the directory discovery looked in, named so a config that
/// silently didn't apply — because it sits somewhere else — is obvious.
List<String> describeConfigSource(
  ConfigFile config, {
  required String projectDir,
}) {
  final path = config.path;

  if (config.ignored) {
    return [
      if (path != null)
        'Ignoring the config file $path (--no-config).'
      else
        'Ignoring any config file (--no-config); there is no $configFileName in $projectDir anyway.',
    ];
  }

  if (path == null) {
    return [
      'No $configFileName in $projectDir; using command-line arguments and built-in defaults.',
    ];
  }

  final settings = config.settings;
  return [
    'Read config from $path.',
    if (settings.isEmpty)
      '  It sets nothing; using command-line arguments and built-in defaults.'
    else ...[
      '  It sets ${settings.length} option${settings.length == 1 ? '' : 's'}:',
      for (final entry in settings.entries)
        '    ${entry.key}: ${_value(entry.value)}',
    ],
  ];
}

/// The `--verbose` rundown of the settings the run actually uses — one line per
/// config key, each naming the layer its value came from, so "why did it behave
/// like that?" is answered without guessing.
///
/// [resolved] supplies the values as the tool ended up using them, and
/// [configuration] the layer each came from. [dartExecutable] is the `dart` the
/// analysis server will be launched with, which only the caller can resolve.
List<String> describeSettings(
  CiachConfiguration configuration,
  ResolvedOptions resolved, {
  required String dartExecutable,
}) => [
  'Settings for this run:',
  for (final option in CiachOption.values)
    if (option.configKey case final key?)
      '  $key: ${_setting(option, resolved, dartExecutable)} (${_source(configuration.valueSourceType(option))})',
];

/// The value of [option] as the run uses it, which for a few settings is not
/// quite the raw resolved value: the root is made absolute, the kinds become
/// labels, and the two auto-detected flags report what they settled on.
String _setting(
  CiachOption<dynamic> option,
  ResolvedOptions resolved,
  String dartExecutable,
) => switch (option) {
  CiachOption.path => resolved.absoluteRootPath,
  CiachOption.public => '${resolved.includePublic}',
  CiachOption.generated => '${resolved.includeGenerated}',
  CiachOption.overrides => '${resolved.overrides}',
  CiachOption.operators => '${resolved.operators}',
  CiachOption.unusedUnionMembers => '${resolved.unusedUnionMembers}',
  CiachOption.reportToJson => '${resolved.reportToJson}',
  CiachOption.setExitIfChanged => '${resolved.setExitIfChanged}',
  CiachOption.remove => '${resolved.remove}',
  CiachOption.force => '${resolved.force}',
  CiachOption.exclude => _value(resolved.excludeGlobs),
  CiachOption.include => _value(resolved.includeGlobs),
  CiachOption.generatedSuffix => _value(resolved.additionalGeneratedSuffixes),
  CiachOption.kinds => _kinds(resolved.kinds),
  CiachOption.format => resolved.format,
  CiachOption.color => '${resolved.useColor}',
  CiachOption.progress => '${resolved.showProgress}',
  CiachOption.verbose => '${resolved.verbose}',
  CiachOption.concurrency => '${resolved.concurrency}',
  CiachOption.dart => dartExecutable,
  // Listed by config key, and these three have none — they decide whether a
  // config file is read at all. Spelled out rather than left to a wildcard so
  // that a new option has to be given a value here.
  CiachOption.help || CiachOption.config || CiachOption.noConfig => '',
};

/// Where a value came from, in the words the user would use for it.
String _source(ValueSourceType source) => switch (source) {
  .arg => 'command line',
  .config => 'config file',
  .envVar => 'environment',
  .preset || .custom => 'preset',
  .defaultValue => 'default',
  .noValue => 'auto-detected',
};

/// A value as it reads in the verbose log: an empty list is `(none)`, a
/// non-empty one is comma-separated, everything else is itself.
String _value(Object? value) => switch (value) {
  [] => '(none)',
  List() => value.join(', '),
  _ => '$value',
};

/// The kind labels, sorted. Whether they are all of them is already clear from
/// the source: nothing restricted them if the value came from the default.
String _kinds(Set<SymbolKind> kinds) =>
    kinds.map((kind) => kind.label).sorted().join(', ');
