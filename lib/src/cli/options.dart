import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:path/path.dart' as p;

/// Everything a run needs, after merging the three layers that can supply a
/// setting: the command line wins over the config file, which wins over the
/// built-in defaults.
///
/// Nothing downstream asks where a setting came from, so this is the last type
/// in the CLI that knows: past here the settings are plain, non-nullable
/// values. [finderOptions] hands the finder's share of them over to the
/// library's own [FinderOptions].
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

  /// Package root to analyze, as written — still relative to the cwd. Use
  /// [absoluteRootPath] for the resolved location.
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

  /// [rootPath] resolved against the current directory, which is what the
  /// finder, the remover and the reporters all work in terms of.
  String get absoluteRootPath => p.normalize(p.absolute(rootPath));

  /// The finder's share of these settings, reporting progress to [onProgress].
  FinderOptions finderOptions({void Function(String message)? onProgress}) =>
      FinderOptions(
        rootPath: absoluteRootPath,
        includeGlobs: includeGlobs,
        excludeGlobs: excludeGlobs,
        additionalGeneratedSuffixes: additionalGeneratedSuffixes,
        kinds: kinds,
        includePublic: includePublic,
        includeGenerated: includeGenerated,
        skipOverrides: !overrides,
        skipOperators: !operators,
        unusedUnionMembers: unusedUnionMembers,
        reportToJson: reportToJson,
        concurrency: concurrency,
        dartExecutable: dartExecutable,
        onProgress: onProgress,
      );
}

/// Merges [args] over [config] over the built-in defaults.
///
/// A command-line flag counts as given only when it was actually parsed, so an
/// option left off the command line falls through to the config file. The two
/// auto-detected settings take their last resort from [colorDefault] and
/// [progressDefault], which the caller probes off the terminal.
///
/// This is the only place that reads every config key, which is what keeps the
/// config file honest: a value of the wrong type — or an unknown `--kinds` or
/// non-positive `--concurrency` from either layer — throws a [FormatException]
/// with a user-facing message naming what was wrong.
ResolvedOptions resolveOptions(
  ArgResults args,
  ConfigFile config, {
  required bool colorDefault,
  required bool progressDefault,
}) {
  // Each helper reads the config value *before* deciding whether to use it, so
  // a malformed setting is still reported when the command line happens to
  // override that same option — the file is wrong either way.

  /// A flag: the config value only shows through when the argv omits it.
  bool flag(String name, {required bool defaultsTo}) {
    final fromConfig = config.boolean(name);
    return args.wasParsed(name) ? args.flag(name) : fromConfig ?? defaultsTo;
  }

  /// A repeatable option; an empty argv list means "not given". The command
  /// line replaces the config's list rather than adding to it.
  List<String> multi(String name, [List<String>? fromConfig]) {
    final values = args.multiOption(name);
    return values.isNotEmpty ? values : fromConfig ?? const [];
  }

  final rest = args.rest;
  final verbose = flag('verbose', defaultsTo: false);
  // Read on its own rather than behind `!verbose &&`, which would short-circuit
  // past the config read — and so past its type check — on a verbose run.
  final progress = flag('progress', defaultsTo: progressDefault);
  final configPath = config.string('path');
  final configDart = config.string('dart');
  final configFormat = config.oneOf('format', formatNames);

  final int concurrency;
  final configConcurrency = config.positiveInt('concurrency');
  final rawConcurrency = args.wasParsed('concurrency')
      ? args.option('concurrency')!
      : configConcurrency?.toString() ?? defaultConcurrency;
  try {
    concurrency = int.parse(rawConcurrency);
    if (concurrency < 1) {
      throw const FormatException();
    }
  } on FormatException {
    throw const FormatException('--concurrency must be a positive integer.');
  }

  return ResolvedOptions(
    rootPath: rest.isNotEmpty ? rest.first : configPath ?? '.',
    includeGlobs: multi('include', config.strings('include')),
    excludeGlobs: multi('exclude', config.strings('exclude')),
    additionalGeneratedSuffixes: multi(
      'generated-suffix',
      config.strings('generated-suffix'),
    ),
    // Throws a FormatException naming the offending kind, as documented.
    kinds: parseKinds(multi('kinds', config.kinds('kinds'))),
    includePublic: flag('public', defaultsTo: true),
    includeGenerated: flag('generated', defaultsTo: false),
    overrides: flag('overrides', defaultsTo: false),
    operators: flag('operators', defaultsTo: false),
    unusedUnionMembers: flag('unused-union-members', defaultsTo: false),
    reportToJson: flag('report-tojson', defaultsTo: false),
    setExitIfChanged: flag('set-exit-if-changed', defaultsTo: false),
    remove: flag('remove', defaultsTo: false),
    force: flag('force', defaultsTo: false),
    format: args.wasParsed('format')
        ? args.option('format')!
        : configFormat ?? formatNames.first,
    useColor: flag('color', defaultsTo: colorDefault),
    showProgress: progress && !verbose,
    verbose: verbose,
    concurrency: concurrency,
    dartExecutable: args.option('dart') ?? configDart,
  );
}
