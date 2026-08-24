import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/models.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

/// The `--verbose` account of the config file: read (and what it set), skipped,
/// or missing from [projectDir], which is named so a file that sits elsewhere
/// and silently didn't apply is obvious.
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

/// The `--verbose` rundown of the run's settings: one line per config key, each
/// naming the layer its value came from.
///
/// [resolved] supplies the values, [configuration] their layers, and
/// [dartExecutable] the `dart` only the caller can resolve.
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

/// The value of [option] as the run uses it, with the root made absolute, the
/// kinds as labels, and the auto-detected flags as they settled.
String _setting(
  CiachOption<dynamic> option,
  ResolvedOptions resolved,
  String dartExecutable,
) => switch (option) {
  .path => resolved.absoluteRootPath,
  .public => '${resolved.includePublic}',
  .failPublic => '${resolved.failPublic}',
  .generated => '${resolved.includeGenerated}',
  .overrides => '${resolved.overrides}',
  .operators => '${resolved.operators}',
  .unusedUnionMembers => '${resolved.unusedUnionMembers}',
  .reportToJson => '${resolved.reportToJson}',
  .setExitIfChanged => '${resolved.setExitIfChanged}',
  .remove => '${resolved.remove}',
  .force => '${resolved.force}',
  .exclude => _value(resolved.excludeGlobs),
  .include => _value(resolved.includeGlobs),
  .generatedSuffix => _value(resolved.additionalGeneratedSuffixes),
  .kinds => _kinds(resolved.kinds),
  .format => resolved.format,
  .color => '${resolved.useColor}',
  .progress => '${resolved.showProgress}',
  .verbose => '${resolved.verbose}',
  .concurrency => '${resolved.concurrency}',
  .dart => dartExecutable,
  // No config key, so never listed; spelled out so a new option must be too.
  .help || .version || .config || .noConfig => '',
};

/// Where a value came from, in the user's words.
String _source(ValueSourceType source) => switch (source) {
  .arg => 'command line',
  .config => 'config file',
  .envVar => 'environment',
  .preset || .custom => 'preset',
  .defaultValue => 'default',
  .noValue => 'auto-detected',
};

/// A value as the log reads it: an empty list is `(none)`, a full one is
/// comma-separated.
String _value(Object? value) => switch (value) {
  [] => '(none)',
  List() => value.join(', '),
  _ => '$value',
};

/// The kind labels, sorted.
String _kinds(Set<SymbolKind> kinds) =>
    kinds.map((kind) => kind.label).sorted().join(', ');
