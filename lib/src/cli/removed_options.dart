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

/// What a removed option became: the values for the option with the config
/// key `key` to take. No values set it to an empty list.
typedef Replacement = ({String key, List<String> values});

/// The removed flags that became a value of `--also`, by config key.
const _alsoFlags = {
  'overrides': 'overrides',
  'report-tojson': 'tojson',
  'unused-union-members': 'union-members',
};

/// Why ciach reports operator overloads without being asked, for the
/// removed `operators` option and `--also` value.
const _operatorsReported = 'operator overloads are reported by default now';

/// Why the removed `concurrency` option, which set how many requests ciach
/// sent to the analysis server at once, has nothing left to set.
const _noServerRequests =
    'ciach no longer sends requests to an analysis server';

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

/// The config keys of the removed options that had an abbreviation, by the
/// abbreviation.
const _removedAbbreviations = {'j': 'concurrency'};

/// Why setting the removed option [key] to [value] (`true` or `false` for a
/// flag) is not needed any more, or what to use instead, in the config file
/// when [inConfig].
String removedOptionAdvice(
  String key,
  Object? value, {
  required bool inConfig,
}) {
  if (key == 'fail-public' && value == false) {
    return 'every finding counts toward the exit code; to leave out what other packages can import, list those packages in `exported-packages`';
  }
  if (key == 'operators') {
    return '$_operatorsReported, so drop it';
  }
  if (key == 'concurrency') {
    return '$_noServerRequests, so drop it';
  }
  return switch (_replacementFor(key, value)) {
    null => 'that is the default now, so drop it',
    final replacement when inConfig =>
      'use `${replacement.key}: [${replacement.values.map(_quoted).join(', ')}]`',
    (:final key, values: []) => 'use `--$key=`',
    (:final key, :final values) =>
      'use ${values.map((value) => '`--$key ${_quoted(value)}`').join(' ')}',
  };
}

/// What setting the removed option [key] to [value] became, or `null` when
/// that is the default now.
Replacement? _replacementFor(String key, Object? value) =>
    switch ((key, value)) {
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

/// An abbreviated option, such as `-j` in `-j 4` and in `-j4`.
final _abbreviatedOption = RegExp('^-(?<abbreviation>[a-zA-Z])');

/// Why the `--also` value [value] was removed, or `null` when ciach still
/// has it.
String? removedAlsoAdvice(String value) =>
    value == 'operators' ? '$_operatorsReported, so drop it' : null;

/// Why the first removed option or `--also` value in [arguments] is gone and
/// what to do instead, or `null` when they name none.
String? removedOptionMessage(List<String> arguments) => arguments
    .takeWhile((argument) => argument != '--')
    .indexed
    .map(
      (entry) => _removedMessage(
        entry.$2,
        next: arguments.elementAtOrNull(entry.$1 + 1),
      ),
    )
    .nonNulls
    .firstOrNull;

/// Why [argument], which the argument [next] may follow, is a removed option
/// or gives `--also` a removed value, or `null` when it is neither.
String? _removedMessage(String argument, {required String? next}) {
  if (_removedAbbreviations[_abbreviatedOption
          .firstMatch(argument)
          ?.namedGroup('abbreviation')]
      case final name?) {
    return '`${argument.substring(0, 2)}` was removed: ${removedOptionAdvice(name, null, inConfig: false)}.';
  }
  final match = _longOption.firstMatch(argument);
  final name = match?.namedGroup('name');
  if (match == null || name == null) {
    return null;
  }
  // The values of `--also` and `--generated-suffix` may be the next argument.
  final value = match.namedGroup('value') ?? next;
  if (name == 'also') {
    return _removedAlsoMessage(value ?? '');
  }
  if (!removedKeys.contains(name)) {
    return null;
  }
  final setting = name == 'generated-suffix'
      ? value
      : match.namedGroup('negation') == null;
  return '`${argument.split('=').first}` was removed: ${removedOptionAdvice(name, setting, inConfig: false)}.';
}

/// Why the first removed value among the comma-separated [values] of
/// `--also` is gone, or `null` when it names none.
String? _removedAlsoMessage(String values) => values
    .split(',')
    .map((value) => value.trim())
    .map(
      (value) => removedAlsoAdvice(
        value,
      )?.let((advice) => '`--also $value` was removed: $advice.'),
    )
    .nonNulls
    .firstOrNull;
