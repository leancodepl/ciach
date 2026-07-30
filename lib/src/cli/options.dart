import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

/// Everything a run needs, in the types the rest of the tool works in.
///
/// Which layer each value came from is `package:config`'s business — by the
/// time a [ResolvedOptions] exists, a setting is just a value. What this adds
/// on top of the resolved [Configuration] is the conversions the finder wants
/// (`--kinds` names to [SymbolKind]s, the two inverted flags), the terminal
/// fallbacks for the settings that auto-detect, and [finderOptions].
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

/// Resolves every [CiachOption] from [args] and [config], the command line
/// winning over the file and the file over the option's default.
///
/// Throws a [UsageException] listing every problem when a value is missing or
/// malformed, whichever layer it came from.
CiachConfiguration resolveConfiguration(ArgResults args, ConfigFile config) =>
    Configuration.resolve(
      options: CiachOption.values,
      argResults: args,
      configBroker: config,
    );

/// The settings of [configuration] in the types the rest of the tool wants.
///
/// [colorDefault] and [progressDefault] stand in for the two settings that
/// auto-detect when nothing asked for them either way; the caller probes those
/// off the terminal.
ResolvedOptions resolveOptions(
  CiachConfiguration configuration, {
  required bool colorDefault,
  required bool progressDefault,
}) {
  final verbose = configuration.value(CiachOption.verbose);
  final progress =
      configuration.optionalValue(CiachOption.progress) ?? progressDefault;

  return ResolvedOptions(
    rootPath: configuration.value(CiachOption.path),
    includeGlobs: configuration.value(CiachOption.include),
    excludeGlobs: configuration.value(CiachOption.exclude),
    additionalGeneratedSuffixes: configuration.value(
      CiachOption.generatedSuffix,
    ),
    // Already validated by the option; this only converts the names.
    kinds: parseKinds(configuration.value(CiachOption.kinds)),
    includePublic: configuration.value(CiachOption.public),
    includeGenerated: configuration.value(CiachOption.generated),
    overrides: configuration.value(CiachOption.overrides),
    operators: configuration.value(CiachOption.operators),
    unusedUnionMembers: configuration.value(CiachOption.unusedUnionMembers),
    reportToJson: configuration.value(CiachOption.reportToJson),
    setExitIfChanged: configuration.value(CiachOption.setExitIfChanged),
    remove: configuration.value(CiachOption.remove),
    force: configuration.value(CiachOption.force),
    format: configuration.value(CiachOption.format),
    useColor: configuration.optionalValue(CiachOption.color) ?? colorDefault,
    showProgress: progress && !verbose,
    verbose: verbose,
    concurrency: configuration.value(CiachOption.concurrency),
    dartExecutable: configuration.optionalValue(CiachOption.dart),
  );
}
