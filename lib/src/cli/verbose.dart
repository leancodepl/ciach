import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:ciach/src/models.dart';
import 'package:collection/collection.dart';
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

/// The `--verbose` rundown of the settings the run actually uses, after the
/// command line, the config file and the defaults have been merged — the answer
/// to "why did it behave like that?".
///
/// [dartExecutable] is the `dart` the analysis server will be launched with,
/// which only the caller can resolve — it falls back to the SDK running ciach.
List<String> describeSettings(
  ResolvedOptions resolved, {
  required String dartExecutable,
}) => [
  'Settings for this run:',
  '  path: ${resolved.absoluteRootPath}',
  '  public: ${resolved.includePublic}',
  '  generated: ${resolved.includeGenerated}',
  '  overrides: ${resolved.overrides}',
  '  operators: ${resolved.operators}',
  '  unused-union-members: ${resolved.unusedUnionMembers}',
  '  report-tojson: ${resolved.reportToJson}',
  '  set-exit-if-changed: ${resolved.setExitIfChanged}',
  '  remove: ${resolved.remove}',
  '  force: ${resolved.force}',
  '  exclude: ${_value(resolved.excludeGlobs)}',
  '  include: ${_value(resolved.includeGlobs)}',
  '  generated-suffix: ${_value(resolved.additionalGeneratedSuffixes)}',
  '  kinds: ${_kinds(resolved.kinds)}',
  '  format: ${resolved.format}',
  '  color: ${resolved.useColor}',
  '  progress: ${resolved.showProgress}',
  '  verbose: ${resolved.verbose}',
  '  concurrency: ${resolved.concurrency}',
  '  dart: $dartExecutable',
];

/// A value as it reads in the verbose log: an empty list is `(none)`, a
/// non-empty one is comma-separated, everything else is itself.
String _value(Object? value) => switch (value) {
  final List<Object?> list => list.isEmpty ? '(none)' : list.join(', '),
  _ => '$value',
};

/// The kind labels, sorted, plus a note when they are simply all of them.
String _kinds(Set<SymbolKind> kinds) {
  final labels = kinds.map((kind) => kind.label).sorted().join(', ');
  return kinds.length == FinderOptions.defaultKinds.length &&
          kinds.containsAll(FinderOptions.defaultKinds)
      ? '$labels (all)'
      : labels;
}
