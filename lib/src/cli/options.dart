import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/ci.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/option_values.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:config/config.dart';

/// A resolved [Configuration] in the types the rest of the tool works in: kind
/// names converted, the inverted flags flipped, the auto-detected ones settled.
class ResolvedOptions {
  const ResolvedOptions({
    required this.rootPath,
    required this.analysisRootPath,
    required this.includeGlobs,
    required this.excludeGlobs,
    required this.additionalGeneratedGlobs,
    required this.kinds,
    required this.includePublic,
    required this.exportedPackages,
    required this.includeGenerated,
    required this.projectConfig,
    required this.unusedTranslations,
    required this.detected,
    required this.overrides,
    required this.operators,
    required this.unusedUnionMembers,
    required this.reportToJson,
    required this.transitive,
    required this.entryPoints,
    required this.setExitIfChanged,
    required this.ci,
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
  final List<String> additionalGeneratedGlobs;
  final Set<SymbolKind> kinds;
  final bool includePublic;

  /// Globs of the packages whose API is left out; empty to check every
  /// package's.
  final List<String> exportedPackages;
  final bool includeGenerated;
  final bool projectConfig;
  final bool unusedTranslations;

  /// The entry points and generated files that the package's own config
  /// files declare. It is empty when [projectConfig] is turned off.
  final ProjectConfig detected;

  /// Whether to report `@override` members — inverted for the finder.
  final bool overrides;

  /// Whether to report operator overloads — inverted for the finder.
  final bool operators;
  final bool unusedUnionMembers;
  final bool reportToJson;
  final bool transitive;

  /// The project's own entry points, from `entry-points` in the config file.
  final List<EntryPoint> entryPoints;

  /// Whether findings fail the run. On by default on [ci].
  final bool setExitIfChanged;

  /// The CI service the run is on, or `null` for a local run: `--ci` if given,
  /// else what the environment says.
  final CiRunner? ci;
  final bool remove;
  final bool force;

  /// The output format; by default the CI service's annotation format, where
  /// it has one.
  final String format;

  /// `--color`/`--no-color`, or `null` for auto.
  final bool? color;

  /// Whether to show scan progress. Always `false` when [verbose] is set, whose
  /// durable lines the overwriting progress line would fight with, and off by
  /// default on [ci], whose log keeps every overwrite.
  final bool showProgress;

  /// Whether to narrate the run on stderr. On by default on [ci], where the
  /// log is all there is to go on afterwards.
  final bool verbose;
  final int concurrency;
  final String? dartExecutable;

  /// Returns the options for the finder. The entry points and generated files
  /// from [detected] are added to the ones that the user gave.
  FinderOptions finderOptions({String? dartExecutable}) => .new(
    rootPath: rootPath,
    analysisRootPath: analysisRootPath,
    includeGlobs: includeGlobs,
    excludeGlobs: excludeGlobs,
    additionalGeneratedGlobs: [
      ...additionalGeneratedGlobs,
      ...unusedTranslations
          ? detected.generatedGlobsExceptTranslations
          : detected.generatedGlobs,
    ],
    kinds: kinds,
    includePublic: includePublic,
    exportedPackages: exportedPackages,
    includeGenerated: includeGenerated,
    skipOverrides: !overrides,
    skipOperators: !operators,
    unusedUnionMembers: unusedUnionMembers,
    reportToJson: reportToJson,
    transitive: transitive,
    entryPoints: [...entryPoints, ...detected.entryPoints],
    translations: unusedTranslations ? detected.translations : const [],
    concurrency: concurrency,
    dartExecutable: dartExecutable ?? this.dartExecutable,
  );
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

/// The settings of [configuration]. [detectedCi] is the service the environment
/// says the run is on; `--ci` and `--no-ci` overrule it. [progressDefault]
/// applies when progress is unset, outside CI.
ResolvedOptions resolveOptions(
  CiachConfiguration configuration, {
  required bool progressDefault,
  required CiRunner? detectedCi,
}) {
  final rootPath = configuration.value(CiachOption.path);
  final projectConfig = configuration.value(CiachOption.projectConfig);
  final ci = switch (configuration.optionalValue(CiachOption.ci)) {
    null => detectedCi,
    true => detectedCi ?? .other,
    false => null,
  };
  final defaults = ci?.defaults;
  // Already validated by the option; this only splits the values.
  final also = parseAlso(configuration.value(CiachOption.also));
  final verbose =
      configuration.optionalValue(CiachOption.verbose) ??
      defaults?.verbose ??
      false;

  return .new(
    rootPath: rootPath,
    analysisRootPath: configuration.optionalValue(CiachOption.analysisRoot),
    includeGlobs: configuration.value(CiachOption.include),
    excludeGlobs: configuration.value(CiachOption.exclude),
    additionalGeneratedGlobs: configuration.value(CiachOption.generatedGlob),
    // Already validated by the option; this only converts the names.
    kinds: parseKinds(configuration.value(CiachOption.kinds)),
    includePublic: configuration.value(CiachOption.public),
    // An empty value, the command line's way to give none, is no glob.
    exportedPackages: [
      for (final glob in configuration.value(CiachOption.exportedPackages))
        if (glob.isNotEmpty) glob,
    ],
    includeGenerated: configuration.value(CiachOption.generated),
    projectConfig: projectConfig,
    unusedTranslations: configuration.value(CiachOption.unusedTranslations),
    detected: projectConfig ? .read(rootPath.absoluteNormalized) : .none,
    overrides: also.contains('overrides'),
    operators: also.contains('operators'),
    unusedUnionMembers: also.contains('union-members'),
    reportToJson: also.contains('tojson'),
    transitive: configuration.value(CiachOption.transitive),
    entryPoints: configuration.value(CiachOption.entryPoints),
    setExitIfChanged:
        configuration.optionalValue(CiachOption.setExitIfChanged) ??
        defaults?.setExitIfChanged ??
        false,
    ci: ci,
    remove: configuration.value(CiachOption.remove),
    force: configuration.value(CiachOption.force),
    format:
        configuration.optionalValue(CiachOption.format) ??
        defaults?.format ??
        formatNames.first,
    color: configuration.optionalValue(CiachOption.color),
    showProgress:
        !verbose &&
        (configuration.optionalValue(CiachOption.progress) ??
            defaults?.showProgress ??
            progressDefault),
    verbose: verbose,
    concurrency: configuration.value(CiachOption.concurrency),
    dartExecutable: configuration.optionalValue(CiachOption.dart),
  );
}
