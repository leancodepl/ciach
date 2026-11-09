/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// The values `--kinds`, `--also` and `--format` accept, and how they are
/// parsed wherever they come from: the command line or the config file.
library;

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/removed_options.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// The `--kinds` names, mapped to the kinds that they select.
const kindAliases = <String, SymbolKind>{
  'class': .class$,
  'mixin': .mixin,
  'interface': .mixin,
  'enum': .enum$,
  'extension': .extension,
  'extension-type': .extensionType,
  'function': .function,
  'method': .method,
  'constructor': .constructor,
  'field': .field,
  'property': .property,
  'getter': .property,
  'setter': .property,
  'variable': .variable,
  'enum-value': .enumValue,
  'typedef': .typedef,
};

/// The `--kinds` alias names, sorted, for help text and error messages.
String get kindNames => kindAliases.keys.sorted().join(', ');

/// The accepted `--also` values: what is skipped by default, each a known
/// source of false positives.
const alsoNames = ['overrides', 'tojson', 'union-members'];

/// Parses the `--also` values (comma-separated, repeatable).
///
/// Throws a [FormatException] naming the offending value on an unknown one,
/// which the command line would catch by itself, but a config file would not.
Set<String> parseAlso(List<String> raw) {
  final names = {
    for (final entry in raw)
      for (final name in entry.split(','))
        if (name.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
  };
  String? removedValue(String name) =>
      removedAlsoAdvice(name)?.let((advice) => removedMessage(name, advice));
  if (names.map(removedValue).nonNulls.firstOrNull case final message?) {
    throw FormatException(message);
  }
  if (names.whereNot(alsoNames.contains).firstOrNull case final unknown?) {
    throw FormatException(
      "Unknown value '$unknown' for `also`. Valid values: ${alsoNames.join(', ')}.",
    );
  }
  return names;
}

/// The accepted `--format` values; the first one is the default, except on a
/// CI service with an annotation format, where it is that one.
const formatNames = [
  'text',
  'json',
  'github',
  'azure',
  'teamcity',
  'sarif',
  'checkstyle',
  'gitlab',
];

/// Parses the `--kinds` values (comma-separated, repeatable) into kinds,
/// falling back to [FinderOptions.defaultKinds] when none are given.
///
/// Throws a [FormatException] naming the offending value on a removed or an
/// unknown kind.
Set<SymbolKind> parseKinds(List<String> raw) {
  if (raw.isEmpty) {
    return FinderOptions.defaultKinds;
  }
  return {
    for (final entry in raw)
      for (final name in entry.split(','))
        if (name.trim().toLowerCase() case final trimmed
            when trimmed.isNotEmpty)
          kindAliases[trimmed] ?? (throw _kindError(trimmed)),
  };
}

/// The error for the `--kinds` value [name], which selects no kind.
FormatException _kindError(String name) => .new(
  removedKindAdvice(name)?.let((advice) => removedMessage(name, advice)) ??
      "Unknown kind '$name'. Valid kinds: $kindNames.",
);
