/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/cli/removed_options.dart';
import 'package:test/test.dart';

void main() {
  test(
    'removedOptionMessage says that operator overloads are reported now, for `operators` given to `--also` either way',
    () {
      expect(
        [
          removedOptionMessage(['--also', 'operators']),
          removedOptionMessage(['--also=tojson,operators']),
          removedOptionMessage(['--also', 'tojson']),
        ],
        [
          '`--also operators` was removed: operator overloads are reported by default now, so drop it.',
          '`--also operators` was removed: operator overloads are reported by default now, so drop it.',
          null,
        ],
      );
    },
  );

  test(
    'removedOptionMessage says that ciach no longer sends requests to an analysis server, for `--concurrency` and `-j` in each spelling',
    () {
      expect(
        [
          removedOptionMessage(['--concurrency', '4']),
          removedOptionMessage(['--concurrency=4']),
          removedOptionMessage(['lib', '-j', '4']),
          removedOptionMessage(['-j4']),
          removedOptionMessage(['-k', 'class']),
        ],
        [
          '`--concurrency` was removed: ciach no longer sends requests to an analysis server, so drop it.',
          '`--concurrency` was removed: ciach no longer sends requests to an analysis server, so drop it.',
          '`-j` was removed: ciach no longer sends requests to an analysis server, so drop it.',
          '`-j` was removed: ciach no longer sends requests to an analysis server, so drop it.',
          null,
        ],
      );
    },
  );

  test('removedOptionMessage names what replaced a removed flag', () {
    expect(
      removedOptionMessage(['lib', '--no-fail-public']),
      startsWith('`--no-fail-public` was removed: '),
    );
    expect(
      removedOptionMessage(['--report-tojson']),
      '`--report-tojson` was removed: use `--also tojson`.',
    );
    expect(
      removedOptionMessage(['--no-operators']),
      '`--no-operators` was removed: operator overloads are reported by default now, so drop it.',
    );
    expect(
      removedOptionMessage(['--exported']),
      '`--exported` was removed: that is the default now, so drop it.',
    );
    expect(
      removedOptionMessage(['--no-exported']),
      "`--no-exported` was removed: use `--exported-packages '**'`.",
    );
    expect(
      removedOptionMessage(['--generated-suffix', '.gc.dart']),
      "`--generated-suffix` was removed: use `--generated-glob '**/*.gc.dart'`.",
    );
    expect(
      removedOptionMessage(['--fail-public']),
      '`--fail-public` was removed: that is the default now, so drop it.',
    );
    expect(removedOptionMessage(['--', '--overrides']), isNull);
    expect(removedOptionMessage(['--also', 'overrides']), isNull);
  });
}
