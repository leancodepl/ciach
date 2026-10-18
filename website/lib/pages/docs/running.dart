/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _usage = r'''
$ dart install ciach
$ ciach                                  # current package
$ ciach path/to/package                  # another package
$ ciach --no-public -f json              # private-only, as JSON
$ ciach -f github --set-exit-if-changed  # CI: annotations, non-zero on finds
$ ciach --remove                         # delete findings, asks first''';

class const RunningSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'running',
    heading: 'Running ciach',
    children: [
      const Terminal(transcript: _usage, title: 'usage'),
      p(
        rich(
          'Run `dart pub get` first in every package ciach scans, nested ones '
          'included. Otherwise ciach stops with exit code `2` and names the '
          'package; `--exclude` skips a nested package instead. In a pub '
          'workspace, `pub get` in the root covers every member.',
        ),
      ),
      p(
        rich(
          'The report goes to stdout. Progress, `-v` output, warnings, errors '
          'and the `--remove` prompt go to stderr, so `ciach -f json | jq` '
          'works.',
        ),
      ),
      p(
        rich(
          'Exit codes: `0` success, `1` something found with `--set-exit-if-changed`, `2` a usage or analysis error.',
        ),
      ),
    ],
  );
}
