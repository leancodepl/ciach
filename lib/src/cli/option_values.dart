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
import 'package:collection/collection.dart';

/// Friendly `--kinds` names mapped to LSP symbol kinds.
const kindAliases = <String, SymbolKind>{
  'class': .class$,
  'mixin': .interface$,
  'interface': .interface$,
  'enum': .enum$,
  'extension': .namespace,
  'extension-type': .struct,
  'function': .function,
  'method': .method,
  'constructor': .constructor,
  'field': .field,
  'property': .property,
  'getter': .property,
  'setter': .property,
  'variable': .variable,
  'constant': .constant,
  'enum-value': .enumMember,
};

/// The `--kinds` alias names, sorted, for help text and error messages.
String get kindNames => kindAliases.keys.sorted().join(', ');

/// The accepted `--also` values: what is skipped by default, each a known
/// source of false positives.
const alsoNames = ['overrides', 'tojson', 'union-members'];

/// The values in [raw], whose entries each hold comma-separated `also`
/// values.
Set<String> splitAlso(Iterable<String> raw) => {
  for (final entry in raw)
    for (final name in entry.split(','))
      if (name.trim() case final trimmed when trimmed.isNotEmpty) trimmed,
};

/// Why the removed `operators` options, `operators` under `also` included,
/// are not needed.
const operatorsReported = 'operators are reported by default now';

/// Parses the `--also` values (comma-separated, repeatable).
///
/// Throws a [FormatException] naming the offending value on an unknown one,
/// which the command line would catch by itself, but a config file would not.
Set<String> parseAlso(List<String> raw) {
  final names = splitAlso(raw);
  if (names.contains('operators')) {
    throw const FormatException(
      '`operators` under `also` was removed: $operatorsReported, so drop it.',
    );
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

/// Parses the `--kinds` values (comma-separated, repeatable) into symbol kinds,
/// falling back to [FinderOptions.defaultKinds] when none are given.
///
/// Throws a [FormatException] naming the offending value on an unknown kind.
Set<SymbolKind> parseKinds(List<String> raw) {
  if (raw.isEmpty) {
    return FinderOptions.defaultKinds;
  }
  return {
    for (final entry in raw)
      for (final name in entry.split(','))
        if (name.trim().toLowerCase() case final trimmed
            when trimmed.isNotEmpty)
          kindAliases[trimmed] ??
              (throw FormatException(
                "Unknown kind '$trimmed'. Valid kinds: $kindNames.",
              )),
  };
}
