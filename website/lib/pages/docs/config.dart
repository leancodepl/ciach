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
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _config = '''
public: false                     # --no-public
analysis-root: ..                 # --analysis-root
exported-packages: [packages/api] # see Library packages
exclude: ['test/**', 'tool/**']   # a repeatable option takes a list, or one string
kinds: [class, function, method]
format: github
set-exit-if-changed: true
entry-points:                     # config file only; see Entry points
  - name: bootstrap
    glob: 'lib/src/isolate.dart\'''';

Component configSection() => DocSection(
  id: 'config',
  heading: 'Configuration file',
  children: [
    p(
      rich(
        'Every option except `--help`, `--version`, `--config` and '
        '`--no-config` can live in a `ciach.yaml` in the package root, keyed '
        'by its long name without the `--`, plus `path` for the positional '
        'argument:',
      ),
    ),
    const CodeBlock(source: _config, language: .yaml, title: 'ciach.yaml'),
    p(
      rich(
        'The command line wins over the file, and the file over the default. '
        "A repeatable option on the command line replaces the file's list. "
        'An unknown key or a wrong type is an error naming the file and the '
        'key. Discovery looks in the analyzed package root only, so each '
        'package in a monorepo owns its config; `--config <path>` reads one '
        'from elsewhere, `--no-config` ignores it.',
      ),
    ),
    p([
      const .text(
        'Options from earlier versions are errors that say what to use instead. ',
      ),
      externalLink(migrationUrl, [const .text('MIGRATION.md')]),
      const .text(' lists them.'),
    ]),
  ],
);
