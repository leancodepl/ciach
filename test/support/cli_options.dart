/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves options as the CLI does, and matches the errors that the config
/// file and the command line throw.
library;

import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/ci.dart';
import 'package:ciach/src/cli/config.dart';
import 'package:ciach/src/cli/options.dart';
import 'package:config/config.dart';
import 'package:test/test.dart';

final _parser = buildParser();

/// Resolves [arguments] against [config], the environment-probed defaults
/// given explicitly so no test depends on the terminal or CI it runs in.
ResolvedOptions resolveWith(
  List<String> arguments,
  ConfigFile config, {
  required bool progressDefault,
  CiRunner? detectedCi,
}) => resolveOptions(
  resolveConfiguration(_parser.parse(arguments), config),
  progressDefault: progressDefault,
  detectedCi: detectedCi,
);

/// Resolves [arguments] against [config] as [resolveWith] does, with
/// progress off unless asked for.
ResolvedOptions resolve(List<String> arguments, [ConfigFile? config]) =>
    resolveWith(arguments, config ?? const .empty(), progressDefault: false);

/// What a config [source] alone resolves to.
ResolvedOptions resolveFile(String source) =>
    resolve(const [], .parse(source, origin: 'ciach.yaml'));

/// A [UsageException] whose message matches [message].
Matcher isUsageException(Matcher message) =>
    isA<UsageException>().having((e) => e.message, 'message', message);

/// A [FormatException] whose message names [origin] and matches [message].
Matcher isFormatExceptionFrom(String origin, Matcher message) =>
    isA<FormatException>()
        .having((e) => e.message, 'message', startsWith('$origin:'))
        .having((e) => e.message, 'message', message);
