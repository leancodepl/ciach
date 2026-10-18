/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _options = [
  ('--no-public', 'Report private declarations only. Cheapest mode.'),
  (
    '--exported-packages <glob>',
    'Packages that code outside the analysis imports, such as one published to pub.dev, whose API is not reported.',
  ),
  (
    '--remove, --force',
    'Delete what was found after confirming. `--force` skips the prompt.',
  ),
  (
    '-f <format>',
    'text, json, github, azure, teamcity, sarif, checkstyle or gitlab.',
  ),
  (
    '--set-exit-if-changed',
    'Exit 1 when anything is found. On by default in CI.',
  ),
  (
    '-k, --kinds',
    'Restrict to declaration kinds, e.g. `class,function,method`.',
  ),
  (
    '-i, -e',
    'Include or exclude file globs. References are still counted from everywhere.',
  ),
  (
    '--analysis-root',
    'Count references from a whole monorepo, not just the scanned package. What is scanned and removed is unchanged.',
  ),
  (
    '--no-transitive',
    'Report only declarations that nothing uses. By default, a declaration used only by other dead code is reported too, naming what uses it.',
  ),
  (
    '--also overrides,operators,tojson,union-members',
    'Opt back into a category skipped by default.',
  ),
  ('--generated', 'Scan generated files too.'),
  ('-v', 'Narrate the run on stderr with timings.'),
];

Component optionsSection() => DocSection(
  id: 'options',
  heading: 'Options',
  children: [
    docsTable(
      columns: const ['Flag', 'What it does'],
      rows: [
        for (final (flag, what) in _options)
          [
            span([
              // One chip per flag, so a row listing several wraps between
              // them rather than inside one.
              for (final (i, f) in flag.split(', ').indexed) ...[
                if (i > 0) const .text(' '),
                code([.text(f)]),
              ],
            ]),
            span(rich(what)),
          ],
      ],
    ),
    p(classes: Prose.note.name, [
      const code([.text('ciach --help')]),
      const .text(' describes every option; so does the '),
      externalLink(readmeOptionsUrl, [const .text('options table')]),
      const .text(' in the README.'),
    ]),
  ],
);
