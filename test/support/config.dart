import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:config/config.dart';
import 'package:test/test.dart';

/// The command-line parser the options are resolved through.
final argParser = buildParser();

/// Resolves [arguments] against [config], the terminal-probed defaults given
/// explicitly so no test depends on the terminal it runs in.
ResolvedOptions resolveWith(
  List<String> arguments,
  ConfigFile config, {
  required bool progressDefault,
}) => resolveOptions(
  resolveConfiguration(argParser.parse(arguments), config),
  progressDefault: progressDefault,
);

/// As [resolveWith], with progress off unless asked for.
ResolvedOptions resolve(List<String> arguments, [ConfigFile? config]) =>
    resolveWith(arguments, config ?? const .empty(), progressDefault: false);

/// What a config [source] alone resolves to.
ResolvedOptions resolveFile(String source) =>
    resolve(const [], .parse(source, origin: 'ciach.yaml'));

/// A [UsageException] whose message matches [message].
Matcher aUsageException(Matcher message) =>
    isA<UsageException>().having((e) => e.message, 'message', message);

/// A [FormatException] whose message names [origin] and matches [message].
Matcher aFormatException(String origin, Matcher message) =>
    isA<FormatException>()
        .having((e) => e.message, 'message', startsWith('$origin:'))
        .having((e) => e.message, 'message', message);
