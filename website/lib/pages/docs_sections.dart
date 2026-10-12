import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/pages/docs_content.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The sections of the docs page in reading order, each under the id its
/// table of contents links to.
List<Component> docsSections() => [
  _install(),
  _options(),
  _ci(),
  _config(),
  _compared(),
  _removing(),
  _skips(),
  _library(),
  const DocSection(id: 'faq', heading: 'FAQ', children: [Faq()]),
];

Component _install() => const DocSection(
  id: 'install',
  heading: 'Install',
  children: [
    p([
      .text('Globally, as a native '),
      code([.text('ciach')]),
      .text(
        ' binary you can run from anywhere, or as a dev dependency '
        'that pins the version for the team and CI (then prefix '
        'commands with ',
      ),
      code([.text('dart run')]),
      .text('). Requires Dart 3.10+ and analyzes with the SDK it runs with.'),
    ]),
    CodeBlock(
      source: '$installCommand\n$devDependencyCommand',
      language: .shell,
      title: 'install',
      copyText: installCommand,
    ),
    Terminal(transcript: DocsContent.usage, title: 'usage'),
  ],
);

Component _options() => DocSection(
  id: 'options',
  heading: 'Options',
  children: [
    DocsTable(
      head: const [
        th(attributes: {'scope': 'col'}, [.text('Flag')]),
        th(attributes: {'scope': 'col'}, [.text('What it does')]),
      ],
      rows: [
        for (final (flag, what) in DocsContent.options)
          tr([
            th(
              attributes: const {'scope': 'row'},
              [
                // One chip per flag, so a row listing several wraps between
                // them rather than inside one.
                for (final (i, f) in flag.split(', ').indexed) ...[
                  if (i > 0) const .text(' '),
                  code([.text(f)]),
                ],
              ],
            ),
            td(rich(what)),
          ]),
      ],
    ),
    p(classes: Prose.note.name, [
      const .text('Exit codes: 0 clean, 1 findings with '),
      const code([.text('--set-exit-if-changed')]),
      const .text(', 2 usage or analysis error. '),
      externalLink(readmeUrl, [const .text('All options →')]),
    ]),
  ],
);

Component _ci() => const DocSection(
  id: 'ci',
  heading: 'GitHub Actions',
  children: [
    p([
      .text(
        'Each finding becomes an annotation on the diff, and the '
        'job fails when anything is found. Run from the repository '
        'root so paths resolve. For a library whose public API is '
        'legitimately unused from the inside, add ',
      ),
      code([.text('--no-fail-public')]),
      .text('.'),
    ]),
    CodeBlock(
      source: DocsContent.workflow,
      language: .yaml,
      title: '.github/workflows/test.yml',
    ),
  ],
);

Component _config() => const DocSection(
  id: 'config',
  heading: 'Configuration file',
  children: [
    p([
      .text('Every option can live in a '),
      code([.text('ciach.yaml')]),
      .text(
        ' in the package root. Command line beats config file beats '
        'default, and a repeatable option on the command line '
        'replaces the list instead of appending. Discovery looks in '
        'the analyzed package root only, so each package in a '
        'monorepo owns its config; ',
      ),
      code([.text('--config <path>')]),
      .text(' reads one from elsewhere, '),
      code([.text('--no-config')]),
      .text(' ignores it.'),
    ]),
    CodeBlock(source: DocsContent.config, language: .yaml, title: 'ciach.yaml'),
  ],
);

Component _compared() => DocSection(
  id: 'compared',
  heading: 'Compared with the analyzer',
  children: [
    const p([
      .text(
        'The Dart analyzer already flags unused private declarations through ',
      ),
      code([.text('unused_element')]),
      .text(
        ' and friends, one library at a time. ciach starts where that stops.',
      ),
    ]),
    DocsTable(
      compare: true,
      head: const [
        th(attributes: {'scope': 'col'}, [.text('')]),
        th(
          attributes: {'scope': 'col'},
          [
            code([.text('dart analyze')]),
          ],
        ),
        th(
          attributes: {'scope': 'col'},
          [
            code([.text('ciach')]),
          ],
        ),
      ],
      rows: [
        for (final (capability, analyzer, ciach) in DocsContent.comparison)
          tr([
            th(attributes: const {'scope': 'row'}, [.text(capability)]),
            td(
              attributes: const {'data-label': 'dart analyze'},
              [DocsTable.mark(analyzer)],
            ),
            td(
              attributes: const {'data-label': 'ciach'},
              [DocsTable.mark(ciach)],
            ),
          ]),
      ],
    ),
    const p([
      .text(
        'Both resolve references the same way, because ciach asks '
        'the analysis server. The difference is scope and the '
        'removal step. Dart Code Metrics covers unused code as well, '
        'as part of a larger commercial toolset.',
      ),
    ]),
  ],
);

Component _removing() => DocSection(
  id: 'removing',
  heading: 'Removing safely',
  children: [
    const p([
      code([.text('--remove')]),
      .text(
        ' shows what it is about to delete and asks first; with no terminal and no ',
      ),
      code([.text('--force')]),
      .text(
        ', nothing is removed. It deletes whole declarations '
        'with their doc comments and annotations, leaves an '
        'ambiguous ',
      ),
      code([.text('int a = 1, b = 2;')]),
      .text(
        ' alone unless every declarator is unused, and never touches doc-only findings. Run ',
      ),
      code([.text('dart format')]),
      .text(
        ' afterward and review the diff. A file left with nothing but its imports is deleted too.',
      ),
    ]),
    const h3([.text('Report-only: removal would not compile')]),
    ul(classes: Prose.checklist.name, [
      for (final item in DocsContent.reportOnly) li(rich(item)),
    ]),
  ],
);

Component _skips() => DocSection(
  id: 'skips',
  heading: 'What it skips, and what it cannot see',
  children: [
    const p([
      .text(
        'Each default skip is a known false-positive source; the flag opts back in at that cost.',
      ),
    ]),
    DocsTable(
      head: const [
        th(attributes: {'scope': 'col'}, [.text('Skipped')]),
        th(attributes: {'scope': 'col'}, [.text('Why')]),
        th(attributes: {'scope': 'col'}, [.text('Flag')]),
      ],
      rows: [
        for (final (what, why, flag) in DocsContent.skips)
          tr([
            th(
              attributes: const {'scope': 'row'},
              [
                code([.text(what)]),
              ],
            ),
            td(rich(why)),
            td(
              attributes: const {'data-label': 'Opt back in'},
              [
                if (flag != null)
                  code(classes: DocsTable.flag.name, [.text(flag)])
                else
                  span(classes: Utility.muted.name, const [.text('—')]),
              ],
            ),
          ]),
      ],
    ),
    const h3([.text('Doc-only findings')]),
    const p([
      .text(
        'A dartdoc link counts as a reference to the analysis '
        'server, but a comment is not a call. Declarations with no '
        'code references are listed separately, never count toward '
        'the exit code and are never removed.',
      ),
    ]),
    const CodeBlock(
      source: DocsContent.docOnly,
      language: .console,
      copyText: '',
    ),
    const h3([.text('Limitations')]),
    ul(classes: Prose.checklist.name, [
      li(
        rich(
          'A library package’s public API is legitimately unused '
          'from the inside: prefer `--no-exported` there. In a '
          'monorepo, `--analysis-root` recovers uses that live in '
          'a sibling package.',
        ),
      ),
      li(
        rich(
          'Reflection, dynamic invocation and names used only from '
          'excluded generated code are invisible to a reference '
          'search.',
        ),
      ),
      li(
        rich(
          "Entry points that the project config does not declare have to be listed under `entry-points` in ciach.yaml or marked with `@pragma('vm:entry-point')`.",
        ),
      ),
      li(
        rich(
          'A package that does not analyze cleanly yields incomplete references.',
        ),
      ),
    ]),
  ],
);

Component _library() => const DocSection(
  id: 'library',
  heading: 'Library API',
  children: [
    p([
      .text('The finder behind the CLI is exported from '),
      code([.text('package:ciach/ciach.dart')]),
      .text(
        '. Options mirror the flags; the result carries every '
        'finding with file, line, kind and qualified name, and '
        'doc-only findings in their own list. The run logs '
        'through ',
      ),
      code([.text('package:logging')]),
      .text('.'),
    ]),
    CodeBlock(
      source: DocsContent.library,
      language: .dart,
      title: 'tool/dead_code.dart',
    ),
  ],
);
