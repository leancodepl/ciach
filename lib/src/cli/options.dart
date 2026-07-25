import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';

/// Everything a run needs, after merging the three layers that can supply a
/// setting: the command line wins over the config file, which wins over the
/// built-in defaults.
class ResolvedOptions {
  /// Creates a fully resolved set of options.
  const ResolvedOptions({
    required this.rootPath,
    required this.includeGlobs,
    required this.excludeGlobs,
    required this.additionalGeneratedSuffixes,
    required this.kinds,
    required this.includePublic,
    required this.includeGenerated,
    required this.overrides,
    required this.operators,
    required this.unusedUnionMembers,
    required this.reportToJson,
    required this.setExitIfChanged,
    required this.remove,
    required this.force,
    required this.format,
    required this.useColor,
    required this.showProgress,
    required this.verbose,
    required this.concurrency,
    required this.dartExecutable,
  });

  /// Package root to analyze, as written (still relative to the cwd).
  final String rootPath;

  /// See [FinderOptions.includeGlobs].
  final List<String> includeGlobs;

  /// See [FinderOptions.excludeGlobs].
  final List<String> excludeGlobs;

  /// See [FinderOptions.additionalGeneratedSuffixes].
  final List<String> additionalGeneratedSuffixes;

  /// See [FinderOptions.kinds].
  final Set<SymbolKind> kinds;

  /// See [FinderOptions.includePublic].
  final bool includePublic;

  /// See [FinderOptions.includeGenerated].
  final bool includeGenerated;

  /// Whether to report `@override` members; the inverse of
  /// [FinderOptions.skipOverrides].
  final bool overrides;

  /// Whether to report operator overloads; the inverse of
  /// [FinderOptions.skipOperators].
  final bool operators;

  /// See [FinderOptions.unusedUnionMembers].
  final bool unusedUnionMembers;

  /// See [FinderOptions.reportToJson].
  final bool reportToJson;

  /// Whether to exit non-zero when anything is found.
  final bool setExitIfChanged;

  /// Whether to remove what is reported.
  final bool remove;

  /// Whether to skip the removal confirmation prompt.
  final bool force;

  /// Output format: one of [formatNames].
  final String format;

  /// Whether to colorize text output.
  final bool useColor;

  /// Whether to show scan progress on stderr. Always `false` when [verbose] is
  /// set: the durable verbose log covers the same phases, and a single
  /// overwriting progress line would fight with it.
  final bool showProgress;

  /// Whether to explain what is happening on stderr.
  final bool verbose;

  /// See [FinderOptions.concurrency].
  final int concurrency;

  /// See [FinderOptions.dartExecutable].
  final String? dartExecutable;
}

/// Merges [args] over [config] over the built-in defaults.
///
/// A command-line flag counts as given only when it was actually parsed, so an
/// option left off the command line falls through to the config file. The two
/// auto-detected settings take their last resort from [colorDefault] and
/// [progressDefault], which the caller probes off the terminal.
///
/// Throws a [FormatException] with a user-facing message on an invalid
/// `--kinds` value or a non-positive `--concurrency`.
ResolvedOptions resolveOptions(
  ArgResults args,
  CiachConfig config, {
  required bool colorDefault,
  required bool progressDefault,
}) {
  /// The config value only shows through for a flag absent from the argv.
  bool flag(String name, bool? fromConfig, {required bool defaultsTo}) =>
      args.wasParsed(name) ? args.flag(name) : fromConfig ?? defaultsTo;

  /// Ditto for a repeatable option: an empty argv list means "not given".
  List<String> multi(String name, List<String>? fromConfig) {
    final values = args.multiOption(name);
    return values.isNotEmpty ? values : fromConfig ?? const [];
  }

  final rest = args.rest;
  final verbose = flag('verbose', config.verbose, defaultsTo: false);

  final int concurrency;
  final rawConcurrency = args.wasParsed('concurrency')
      ? args.option('concurrency')!
      : config.concurrency?.toString() ?? defaultConcurrency;
  try {
    concurrency = int.parse(rawConcurrency);
    if (concurrency < 1) {
      throw const FormatException();
    }
  } on FormatException {
    throw const FormatException('--concurrency must be a positive integer.');
  }

  return ResolvedOptions(
    rootPath: rest.isNotEmpty ? rest.first : config.path ?? '.',
    includeGlobs: multi('include', config.include),
    excludeGlobs: multi('exclude', config.exclude),
    additionalGeneratedSuffixes: multi(
      'generated-suffix',
      config.generatedSuffix,
    ),
    // Throws a FormatException naming the offending kind, as documented.
    kinds: parseKinds(multi('kinds', config.kinds)),
    includePublic: flag('public', config.public, defaultsTo: true),
    includeGenerated: flag('generated', config.generated, defaultsTo: false),
    overrides: flag('overrides', config.overrides, defaultsTo: false),
    operators: flag('operators', config.operators, defaultsTo: false),
    unusedUnionMembers: flag(
      'unused-union-members',
      config.unusedUnionMembers,
      defaultsTo: false,
    ),
    reportToJson: flag('report-tojson', config.reportToJson, defaultsTo: false),
    setExitIfChanged: flag(
      'set-exit-if-changed',
      config.setExitIfChanged,
      defaultsTo: false,
    ),
    remove: flag('remove', config.remove, defaultsTo: false),
    force: flag('force', config.force, defaultsTo: false),
    format: args.wasParsed('format')
        ? args.option('format')!
        : config.format ?? formatNames.first,
    useColor: flag('color', config.color, defaultsTo: colorDefault),
    showProgress:
        !verbose &&
        flag('progress', config.progress, defaultsTo: progressDefault),
    verbose: verbose,
    concurrency: concurrency,
    dartExecutable: args.option('dart') ?? config.dart,
  );
}
