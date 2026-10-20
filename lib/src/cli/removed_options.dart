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
  'operators': 'operators',
  'report-tojson': 'tojson',
  'unused-union-members': 'union-members',
};

/// The config keys of the options ciach no longer has.
const removedKeys = {
  'overrides',
  'operators',
  'report-tojson',
  'unused-union-members',
  'exported',
  'fail-public',
  'generated-suffix',
};

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

/// Why the first removed option in [arguments] is gone and what to do
/// instead, or `null` when they name none.
String? removedOptionMessage(List<String> arguments) {
  for (final (i, argument) in arguments.indexed) {
    if (argument == '--') {
      break;
    }
    final match = _longOption.firstMatch(argument);
    final key = match?.namedGroup('name');
    if (match == null || key == null || !removedKeys.contains(key)) {
      continue;
    }
    final Object? value = switch (key) {
      // The value of `--generated-suffix` may be the next argument.
      'generated-suffix' =>
        match.namedGroup('value') ?? arguments.elementAtOrNull(i + 1),
      _ => match.namedGroup('negation') == null,
    };
    return '`${argument.split('=').first}` was removed: ${removedOptionAdvice(key, value, inConfig: false)}.';
  }
  return null;
}
