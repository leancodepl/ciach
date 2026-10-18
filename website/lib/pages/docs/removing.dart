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
import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _prompt = '''
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s)
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.''';

/// The findings that `--remove` leaves in place, and why.
const _reportOnly = [
  (
    'A sealed member matched only by type patterns (`--also union-members`)',
    'its `case` arms would need rewriting',
  ),
  ('A used enum whose values are all unused', "`enum E {}` doesn't compile"),
  (
    'The sole constructor of a live class with `final` fields, or whose superclass needs constructor arguments',
    "the implicit default constructor can't replace it",
  ),
  (
    'A primary constructor or its declaring parameters',
    'only part of the class header',
  ),
  (
    "A member whose override is a declaring parameter, or is in a file the run didn't scan",
    "that override can't be deleted, and would be left overriding nothing",
  ),
  ('A gen-l10n message', 'gen-l10n would generate it again from the ARB file'),
  ('A type that only doc comments mention', 'the links would dangle'),
];

class const RemovingSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'removing',
    heading: 'Removing dead code',
    children: [
      p(
        rich(
          '`--remove` deletes every reported declaration, doc comment and '
          'annotations included, after showing what it is about to remove and '
          'asking:',
        ),
      ),
      const CodeBlock(
        source: _prompt,
        language: .console,
        copyText: '',
        wrap: false,
      ),
      p(
        rich(
          '`--force` skips the prompt. With no terminal to confirm on and no '
          '`--force`, nothing is removed. Run `dart format` afterward: removal '
          "cuts along the analyzer's syntax, so `int a = 1, b = 2;` loses just "
          "`b` or the whole statement, but it doesn't tidy up spacing.",
        ),
      ),
      p(
        rich(
          'Removal acts on whatever the finder reports, so it inherits the '
          'same false-positive risk, which `--also overrides,operators` widens '
          'considerably. Review the diff, as you would after any automated '
          'refactor.',
        ),
      ),
      const DocHeading(
        fragment: 'removed-with',
        text: 'What goes with a removed declaration',
        subsection: true,
      ),
      ul(classes: Prose.checklist.name, [
        li(
          rich(
            'Its overrides, wherever they live: a call through any subclass '
            'would have referenced the member, so they are dead too.',
          ),
        ),
        li(
          rich(
            'A file left with only `library`, `import` or `part of` '
            'directives, an empty file found before removal, and the `import`s '
            'of them elsewhere. A file that still `export`s or owns a `part` '
            'stays.',
          ),
        ),
        li(
          rich(
            'A class or mixin whose members are all unused and that only '
            '`with` or `implements` clauses name is reported and removed whole, '
            'from those clauses too. If other code names it, say as a type or '
            'after `extends`, if it is generic, or if it is the only mixin of '
            '`class A = B with M;`, only its members go, and the summary lists '
            'the emptied declaration.',
          ),
        ),
      ]),
      const DocHeading(
        fragment: 'removed-comments',
        text: 'Comments next to removed code',
        subsection: true,
      ),
      p(
        rich(
          'A plain `//` comment right above a removed declaration stays, '
          'because it may be about the code around it rather than the '
          'declaration. The summary lists each such comment with its line in '
          'the changed file, so you can check whether it still belongs. A '
          'comment with a blank line after it is not listed, and neither is a '
          'comment for a tool, such as `// ciach:ignore-end` or '
          '`// dart format on`.',
        ),
      ),
      p(
        rich(
          'An `// ignore:`, `// expect_lint:` or `// cspell:disable-next-line` '
          'comment right above a removed declaration goes with it, since it '
          'only applies to the next line. So does a `//` comment at the end of '
          'the last line of a removed declaration, or of a removed `import`. A '
          'comment for a tool there, such as `// coverage:ignore-start`, '
          'stays, so the range it opens or closes keeps both ends.',
        ),
      ),
      const DocHeading(
        fragment: 'report-only',
        text: 'Report-only findings',
        subsection: true,
      ),
      p(
        rich(
          'Findings that cannot be removed without breaking the build are '
          'report-only, marked `unsafe to auto-remove — remove manually` and '
          'left in place.',
        ),
      ),
      docsTable(
        columns: const ['Report-only finding', 'Why'],
        rows: [
          for (final (finding, why) in _reportOnly)
            [span(rich(finding)), span(rich(why))],
        ],
      ),
    ],
  );
}
