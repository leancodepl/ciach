import 'package:args/args.dart';
import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;

/// A resolved [Configuration] in the types the rest of the tool works in: kind
/// names converted, the inverted flags flipped, the auto-detected ones settled.
class ResolvedOptions {
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
    required this.concurrency,
    required this.dartExecutable,
  });

  /// Package root to analyze, as written; see [absoluteRootPath].
  final String rootPath;
  final List<String> includeGlobs;
  final List<String> excludeGlobs;
  final List<String> additionalGeneratedSuffixes;
  final Set<SymbolKind> kinds;
  final bool includePublic;
  final bool includeGenerated;

  /// Whether to report `@override` members — inverted for the finder.
  final bool overrides;

  /// Whether to report operator overloads — inverted for the finder.
  final bool operators;
  final bool unusedUnionMembers;
  final bool reportToJson;
  final bool setExitIfChanged;
  final bool remove;
  final bool force;
  final String format;
  final bool useColor;

  /// Whether to show scan progress.
  final bool showProgress;
  final int concurrency;
  final String? dartExecutable;

  /// [rootPath] resolved against the current directory.
  String get absoluteRootPath => p.normalize(p.absolute(rootPath));

  /// The finder's share of these settings, reporting progress to [onProgress].
  FinderOptions finderOptions({void Function(String message)? onProgress}) =>
      .new(
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
/// winning over the file and the file over the default.
///
/// Throws a [UsageException] listing every malformed value, from either layer.
CiachConfiguration resolveConfiguration(ArgResults args, ConfigFile config) =>
    .resolve(
      options: CiachOption.values,
      argResults: args,
      configBroker: config,
    );

/// The settings of [configuration], with [colorDefault] and [progressDefault]
/// standing in for the two nobody asked for either way.
ResolvedOptions resolveOptions(
  CiachConfiguration configuration, {
  required bool colorDefault,
  required bool progressDefault,
}) => .new(
  rootPath: configuration.value(CiachOption.path),
  includeGlobs: configuration.value(CiachOption.include),
  excludeGlobs: configuration.value(CiachOption.exclude),
  additionalGeneratedSuffixes: configuration.value(CiachOption.generatedSuffix),
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
  showProgress:
      configuration.optionalValue(CiachOption.progress) ?? progressDefault,
  concurrency: configuration.value(CiachOption.concurrency),
  dartExecutable: configuration.optionalValue(CiachOption.dart),
);
