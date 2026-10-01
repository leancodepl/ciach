import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/paths.dart';
import 'package:config/config.dart';

/// A resolved [Configuration] in the types the rest of the tool works in: kind
/// names converted, the inverted flags flipped, the auto-detected ones settled.
class ResolvedOptions {
  const ResolvedOptions({
    required this.rootPath,
    required this.analysisRootPath,
    required this.includeGlobs,
    required this.excludeGlobs,
    required this.additionalGeneratedSuffixes,
    required this.additionalGeneratedGlobs,
    required this.kinds,
    required this.includePublic,
    required this.failPublic,
    required this.includeGenerated,
    required this.projectConfig,
    required this.overrides,
    required this.operators,
    required this.unusedUnionMembers,
    required this.reportToJson,
    required this.transitive,
    required this.entryPoints,
    required this.setExitIfChanged,
    required this.remove,
    required this.force,
    required this.format,
    required this.color,
    required this.showProgress,
    required this.verbose,
    required this.concurrency,
    required this.dartExecutable,
  });

  /// Package root to analyze, as written. [FinderOptions] normalizes it.
  final String rootPath;

  /// The directory to analyze within, as written, or `null` for [rootPath]
  /// itself.
  final String? analysisRootPath;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final List<String> additionalGeneratedSuffixes;
  final List<String> additionalGeneratedGlobs;
  final Set<SymbolKind> kinds;
  final bool includePublic;
  final bool failPublic;
  final bool includeGenerated;
  final bool projectConfig;

  /// Whether to report `@override` members — inverted for the finder.
  final bool overrides;

  /// Whether to report operator overloads — inverted for the finder.
  final bool operators;
  final bool unusedUnionMembers;
  final bool reportToJson;
  final bool transitive;

  /// The project's own entry points, from `entry-points` in the config file.
  final List<EntryPoint> entryPoints;
  final bool setExitIfChanged;
  final bool remove;
  final bool force;
  final String format;

  /// `--color`/`--no-color`, or `null` for auto.
  final bool? color;

  /// Whether to show scan progress. Always `false` when [verbose] is set, whose
  /// durable lines the overwriting progress line would fight with.
  final bool showProgress;
  final bool verbose;
  final int concurrency;
  final String? dartExecutable;

  /// The finder's options, with what [projectConfig] reads merged in.
  FinderOptions finderOptions({String? dartExecutable}) {
    final detected = projectConfig
        ? ProjectConventions.read(rootPath.absoluteNormalized)
        : ProjectConventions.none;
    return .new(
      rootPath: rootPath,
      analysisRootPath: analysisRootPath,
      includeGlobs: includeGlobs,
      excludeGlobs: excludeGlobs,
      additionalGeneratedSuffixes: additionalGeneratedSuffixes,
      additionalGeneratedGlobs: [
        ...additionalGeneratedGlobs,
        ...detected.generatedGlobs,
      ],
      kinds: kinds,
      includePublic: includePublic,
      includeGenerated: includeGenerated,
      skipOverrides: !overrides,
      skipOperators: !operators,
      unusedUnionMembers: unusedUnionMembers,
      reportToJson: reportToJson,
      transitive: transitive,
      entryPoints: [...entryPoints, ...detected.entryPoints],
      serverpodEndpoints: detected.serverpod,
      concurrency: concurrency,
      dartExecutable: dartExecutable ?? this.dartExecutable,
    );
  }
}

/// Resolves every [CiachOption] from [args] and [config], the command line
/// winning over the file and the file over the default.
///
/// Throws a [UsageException] listing every malformed value, from either layer.
CiachConfiguration resolveConfiguration(ArgResults args, ConfigFile config) =>
    .resolve(
      options: CiachOption.values,
      argResults: args,
      configBroker: config,
    );

/// The settings of [configuration]; [progressDefault] applies when progress
/// is unset.
ResolvedOptions resolveOptions(
  CiachConfiguration configuration, {
  required bool progressDefault,
}) {
  final verbose = configuration.value(CiachOption.verbose);

  return .new(
    rootPath: configuration.value(CiachOption.path),
    analysisRootPath: configuration.optionalValue(CiachOption.analysisRoot),
    includeGlobs: configuration.value(CiachOption.include),
    excludeGlobs: configuration.value(CiachOption.exclude),
    additionalGeneratedSuffixes: configuration.value(
      CiachOption.generatedSuffix,
    ),
    additionalGeneratedGlobs: configuration.value(CiachOption.generatedGlob),
    // Already validated by the option; this only converts the names.
    kinds: parseKinds(configuration.value(CiachOption.kinds)),
    includePublic: configuration.value(CiachOption.public),
    failPublic: configuration.value(CiachOption.failPublic),
    includeGenerated: configuration.value(CiachOption.generated),
    projectConfig: configuration.value(CiachOption.projectConfig),
    overrides: configuration.value(CiachOption.overrides),
    operators: configuration.value(CiachOption.operators),
    unusedUnionMembers: configuration.value(CiachOption.unusedUnionMembers),
    reportToJson: configuration.value(CiachOption.reportToJson),
    transitive: configuration.value(CiachOption.transitive),
    entryPoints: configuration.value(CiachOption.entryPoints),
    setExitIfChanged: configuration.value(CiachOption.setExitIfChanged),
    remove: configuration.value(CiachOption.remove),
    force: configuration.value(CiachOption.force),
    format: configuration.value(CiachOption.format),
    color: configuration.optionalValue(CiachOption.color),
    showProgress:
        !verbose &&
        (configuration.optionalValue(CiachOption.progress) ?? progressDefault),
    verbose: verbose,
    concurrency: configuration.value(CiachOption.concurrency),
    dartExecutable: configuration.optionalValue(CiachOption.dart),
  );
}
