/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// The options earlier versions accepted, each an error naming what to use
/// instead.
library;

import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// The removed flags that became a value of `--also`, by config key.
const _alsoFlags = {
  'overrides': 'overrides',
  'report-tojson': 'tojson',
  'unused-union-members': 'union-members',
};

/// Why the removed `operators` option and `--also` value are not needed.
const _operatorsReported =
    'operator overloads are reported by default now, so drop it';

/// The config keys of the options ciach no longer has.
const removedKeys = {
  'overrides',
  'operators',
  'report-tojson',
  'unused-union-members',
  'exported',
  'fail-public',
  'generated-suffix',
  'concurrency',
};

/// Why setting the removed option [key] to [value] (`true` or `false` for a
/// flag) is not needed any more, or what to use instead, in the config file
/// when [inConfig].
String removedOptionAdvice(
  String key,
  Object? value, {
  required bool inConfig,
}) => switch ((key, value)) {
  ('fail-public', false) =>
    'every finding counts toward the exit code; to leave out what other packages can import, list those packages in `exported-packages`',
  ('operators', _) => _operatorsReported,
  // It set how many requests ciach sent to the analysis server at once.
  ('concurrency', _) =>
    'ciach no longer sends requests to an analysis server, so drop it',
  _ => switch (_replacementFor(key, value)) {
    null => 'that is the default now, so drop it',
    final replacement when inConfig =>
      'use `${replacement.key}: [${replacement.values.map(_quoted).join(', ')}]`',
    (:final key, values: []) => 'use `--$key=`',
    (:final key, :final values) =>
      'use ${values.map((value) => '`--$key ${_quoted(value)}`').join(' ')}',
  },
};

/// What setting the removed option [key] to [value] became: the values for
/// the option with the config key `key` to take, none setting it to an empty
/// list. `null` when that is the default now.
({String key, List<String> values})? _replacementFor(
  String key,
  Object? value,
) => switch ((key, value)) {
  ('exported', false) => (key: 'exported-packages', values: const ['**']),
  ('generated-suffix', final Iterable<Object?> suffixes) => (
    key: 'generated-glob',
    values: [for (final suffix in suffixes) '**/*$suffix'],
  ),
  ('generated-suffix', final suffix) => (
    key: 'generated-glob',
    values: ['**/*${suffix ?? '<suffix>'}'],
  ),
  (final flag, true) => _alsoFlags[flag]?.let(
    (also) => (key: 'also', values: [also]),
  ),
  _ => null,
};

/// [value], single-quoted when a shell or YAML would read it otherwise.
String _quoted(String value) =>
    RegExp(r'^[\w.-]+$').hasMatch(value) ? value : "'$value'";

final _longOption = RegExp(
  r'^--(?<negation>no-)?(?<name>[\w-]+)(?:=(?<value>.*))?$',
);

/// Why the `--also` value [value] was removed, or `null` when ciach still
/// has it.
String? removedAlsoAdvice(String value) =>
    value == 'operators' ? _operatorsReported : null;

/// Why the `--kinds` value [value] was removed, or `null` when ciach still
/// has it.
String? removedKindAdvice(String value) => value == 'constant'
    ? 'ciach reports a `const` variable as a `variable` or a `field`, so use those'
    : null;

/// Why the first removed option or `--also` value in [arguments] is gone and
/// what to do instead, or `null` when they name none.
String? removedOptionMessage(List<String> arguments) => arguments
    .takeWhile((argument) => argument != '--')
    .mapIndexed(
      (i, argument) =>
          _removedMessage(argument, next: arguments.elementAtOrNull(i + 1)),
    )
    .nonNulls
    .firstOrNull;

/// Why [argument], which the argument [next] may follow, is a removed option
/// or gives `--also` a removed value, or `null` when it is neither.
String? _removedMessage(String argument, {required String? next}) {
  // `-j`, in `-j 4` and in `-j4`, was short for `--concurrency`.
  if (argument.startsWith('-j')) {
    return removedMessage(
      '-j',
      removedOptionAdvice('concurrency', null, inConfig: false),
    );
  }
  final match = _longOption.firstMatch(argument);
  if (match == null) {
    return null;
  }
  final name = match.namedGroup('name')!;
  // The values of `--also` and `--generated-suffix` may be the next argument.
  final value = match.namedGroup('value') ?? next;
  if (name == 'also') {
    return value?.let(_removedAlsoMessage);
  }
  if (!removedKeys.contains(name)) {
    return null;
  }
  final setting = name == 'generated-suffix'
      ? value
      : match.namedGroup('negation') == null;
  return removedMessage(
    argument.split('=').first,
    removedOptionAdvice(name, setting, inConfig: false),
  );
}

/// The message that [option] was removed, with [advice] on what to do.
String removedMessage(String option, String advice) =>
    '`$option` was removed: $advice.';

/// Why the first removed value among the comma-separated [values] of
/// `--also` is gone, or `null` when it names none.
String? _removedAlsoMessage(String values) => values
    .split(',')
    .map((value) => value.trim())
    .map(
      (value) => removedAlsoAdvice(
        value,
      )?.let((advice) => removedMessage('--also $value', advice)),
    )
    .nonNulls
    .firstOrNull;
