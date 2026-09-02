import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/docs_toc.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _usage = r'''
$ dart pub global activate ciach
$ ciach                                  # current package
$ ciach path/to/package                  # another package
$ ciach --no-public -f json              # private-only, as JSON
$ ciach -f github --set-exit-if-changed  # CI: annotations, non-zero on finds
$ ciach --remove                         # delete findings, asks first''';

const _workflow = '''
- run: dart pub get
- run: dart run ciach -f github --set-exit-if-changed''';

const _config = '''
# ciach.yaml — every option, keyed by its long name minus the "--".
public: false                     # --no-public
exclude: ['test/**', 'tool/**']   # repeatable options take a list
kinds: [class, function, method]
format: github
set-exit-if-changed: true''';

const _docOnly = '''
lib/greeting.dart
  15:6  function  danglingFunction  (public)

Referenced only from doc comments — not counted as unused, never removed:
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)''';

const _library = r'''
import 'package:ciach/ciach.dart';

final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();

for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}''';

const _toc = [
  ('install', 'Install'),
  ('options', 'Options'),
  ('ci', 'CI'),
  ('config', 'Configuration'),
  ('compared', 'vs. the analyzer'),
  ('removing', 'Removing'),
  ('skips', 'Skips and limits'),
  ('library', 'Library API'),
  ('faq', 'FAQ'),
];

const _options = [
  (
    '--no-public',
    'Report private declarations only. Cheapest mode; the right '
        'one for library packages.',
  ),
  (
    '--remove, --force',
    'Delete what was found after confirming. `--force` skips '
        'the prompt.',
  ),
  ('-f text|json|github', 'Output format.'),
  (
    '--set-exit-if-changed',
    'Exit 1 when anything is found. Add '
        '`--no-fail-public` to count only private findings.',
  ),
  (
    '-k, --kinds',
    'Restrict to declaration kinds, e.g. `class,function,method`.',
  ),
  (
    '-i, -e',
    'Include or exclude file globs. References are still counted '
        'from everywhere.',
  ),
  (
    '--overrides, --operators, --generated, --report-tojson',
    'Opt back into a '
        'category skipped by default.',
  ),
  ('-v', 'Narrate the run on stderr with timings.'),
];

const _comparison = [
  ('Unused private declarations', true, true),
  ('Unused public declarations', false, true),
  ('References followed across libraries', false, true),
  ('Removes what it finds', false, true),
  ('GitHub annotations on the pull request', false, true),
  ('JSON output', true, true),
];

const _skips = [
  ('main', 'The entry point is never unused.', null),
  (
    '@override members',
    'Reached polymorphically or by a framework.',
    '--overrides',
  ),
  (
    'Operator overloads',
    'The server does not resolve `a + b` to the declaration.',
    '--operators',
  ),
  (
    'call methods',
    'Implicit-call syntax `obj(…)` is unresolvable the same way.',
    null,
  ),
  (
    "@pragma('vm:entry-point')",
    'Reachable from native code or reflection.',
    null,
  ),
  (
    'Generated files',
    'By filename and the `GENERATED CODE` banner; still opened for analysis.',
    '--generated',
  ),
  (
    'toJson()',
    '`jsonEncode(obj)` calls it by dynamic dispatch.',
    '--report-tojson',
  ),
  ('dartdoc [Xxx] links', 'Not a code reference; reported as doc-only.', null),
];

const _reportOnly = [
  'A sealed member matched only by type patterns (`--unused-union-members`).',
  'Every value of a still-referenced enum.',
  'The sole constructor of a live class with final fields or super forwarding.',
  'A primary constructor or its declaring parameters.',
];

Component _mark(bool yes) => yes
    ? const span(
        classes: 'mark mark-yes',
        attributes: {'aria-label': 'yes'},
        [Component.text('✓')],
      )
    : const span(
        classes: 'mark mark-no',
        attributes: {'aria-label': 'no'},
        [Component.text('—')],
      );

/// Everything past the landing page, on one page with a sticky table of
/// contents. The README on GitHub stays the exhaustive reference.
class DocsPage extends StatelessComponent {
  const DocsPage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return PageShell(
      page: SitePage.docs,
      version: version,
      children: [
        pageHead(
          title: 'Docs — $siteName',
          description:
              'How to install, configure and run ciach, what it skips and '
              'why, how --remove stays safe, the library API and answers to '
              'common questions.',
          path: 'docs',
          structuredData: [faqStructuredData()],
        ),
        div(classes: 'container docs', [
          nav(
            classes: 'docs-nav',
            attributes: const {'aria-label': 'On this page'},
            [
              const p(classes: 'eyebrow', [Component.text('Docs')]),
              DocsToc(
                path: '/docs',
                ids: [for (final (id, _) in _toc) id],
                labels: [for (final (_, label) in _toc) label],
              ),
              p(classes: 'docs-nav-foot', [
                externalLink(readmeUrl, [
                  const Component.text('Full README on GitHub →'),
                ]),
              ]),
            ],
          ),
          div(classes: 'docs-body', [
            const header(classes: 'docs-head', [
              h1([Component.text('Docs')]),
              p(classes: 'lead', [
                Component.text(
                  'Install, configure and run ciach, and read its findings '
                  'with confidence.',
                ),
              ]),
            ]),
            const DocSection(
              id: 'install',
              heading: 'Install',
              children: [
                p([
                  Component.text('Globally, for a '),
                  code([Component.text('ciach')]),
                  Component.text(
                    ' command everywhere, or as a dev dependency that pins the '
                    'version for the team and CI (then prefix commands with ',
                  ),
                  code([Component.text('dart run')]),
                  Component.text(
                    '). Requires Dart 3.10+ and analyzes with the SDK it runs '
                    'with.',
                  ),
                ]),
                CodeBlock(
                  code: '$installCommand\n$devDependencyCommand',
                  language: Language.shell,
                  title: 'install',
                  copyText: installCommand,
                ),
                Terminal(transcript: _usage, title: 'usage'),
              ],
            ),
            DocSection(
              id: 'options',
              heading: 'Options',
              children: [
                div(classes: 'table-wrap', [
                  table(classes: 'table', [
                    const thead([
                      tr([
                        th(
                          attributes: {'scope': 'col'},
                          [Component.text('Flag')],
                        ),
                        th(
                          attributes: {'scope': 'col'},
                          [Component.text('What it does')],
                        ),
                      ]),
                    ]),
                    tbody([
                      for (final (flag, what) in _options)
                        tr([
                          th(
                            attributes: const {'scope': 'row'},
                            [
                              // One chip per flag, so a row listing several
                              // wraps between them rather than inside one.
                              for (final (i, f)
                                  in flag.split(', ').indexed) ...[
                                if (i > 0) const Component.text(' '),
                                code([Component.text(f)]),
                              ],
                            ],
                          ),
                          td(rich(what)),
                        ]),
                    ]),
                  ]),
                ]),
                p(classes: 'note', [
                  const Component.text('Exit codes: 0 clean, 1 findings with '),
                  const code([Component.text('--set-exit-if-changed')]),
                  const Component.text(', 2 usage or analysis error. '),
                  externalLink(readmeUrl, [
                    const Component.text('All options →'),
                  ]),
                ]),
              ],
            ),
            const DocSection(
              id: 'ci',
              heading: 'GitHub Actions',
              children: [
                p([
                  Component.text(
                    'Each finding becomes an annotation on the diff, and the '
                    'job fails when anything is found. Run from the repository '
                    'root so paths resolve. For a library whose public API is '
                    'legitimately unused from the inside, add ',
                  ),
                  code([Component.text('--no-fail-public')]),
                  Component.text('.'),
                ]),
                CodeBlock(
                  code: _workflow,
                  language: Language.yaml,
                  title: '.github/workflows/test.yml',
                ),
              ],
            ),
            const DocSection(
              id: 'config',
              heading: 'Configuration file',
              children: [
                p([
                  Component.text('Every option can live in a '),
                  code([Component.text('ciach.yaml')]),
                  Component.text(
                    ' in the package root. Command line beats config file beats '
                    'default, and a repeatable option on the command line '
                    'replaces the list instead of appending. Discovery looks in '
                    'the analyzed package root only, so each package in a '
                    'monorepo owns its config; ',
                  ),
                  code([Component.text('--config <path>')]),
                  Component.text(' reads one from elsewhere, '),
                  code([Component.text('--no-config')]),
                  Component.text(' ignores it.'),
                ]),
                CodeBlock(
                  code: _config,
                  language: Language.yaml,
                  title: 'ciach.yaml',
                ),
              ],
            ),
            DocSection(
              id: 'compared',
              heading: 'Compared with the analyzer',
              children: [
                const p([
                  Component.text(
                    'The Dart analyzer already flags unused private '
                    'declarations through ',
                  ),
                  code([Component.text('unused_element')]),
                  Component.text(
                    ' and friends, one library at a time. ciach starts where that '
                    'stops.',
                  ),
                ]),
                div(classes: 'table-wrap', [
                  table(classes: 'table table-compare', [
                    const thead([
                      tr([
                        th(attributes: {'scope': 'col'}, [Component.text('')]),
                        th(
                          attributes: {'scope': 'col'},
                          [
                            code([Component.text('dart analyze')]),
                          ],
                        ),
                        th(
                          attributes: {'scope': 'col'},
                          [
                            code([Component.text('ciach')]),
                          ],
                        ),
                      ]),
                    ]),
                    tbody([
                      for (final (capability, analyzer, ciach) in _comparison)
                        tr([
                          th(
                            attributes: const {'scope': 'row'},
                            [Component.text(capability)],
                          ),
                          td(
                            attributes: const {'data-label': 'dart analyze'},
                            [_mark(analyzer)],
                          ),
                          td(
                            attributes: const {'data-label': 'ciach'},
                            [_mark(ciach)],
                          ),
                        ]),
                    ]),
                  ]),
                ]),
                const p([
                  Component.text(
                    'Both resolve references the same way, because ciach asks '
                    'the analysis server. The difference is scope and the '
                    'removal step. Dart Code Metrics covers unused code as well, '
                    'as part of a larger commercial toolset.',
                  ),
                ]),
              ],
            ),
            DocSection(
              id: 'removing',
              heading: 'Removing safely',
              children: [
                const p([
                  code([Component.text('--remove')]),
                  Component.text(
                    ' shows what it is about to delete and asks first; '
                    'with no terminal and no ',
                  ),
                  code([Component.text('--force')]),
                  Component.text(
                    ', nothing is removed. It deletes whole declarations '
                    'with their doc comments and annotations, leaves an '
                    'ambiguous ',
                  ),
                  code([Component.text('int a = 1, b = 2;')]),
                  Component.text(
                    ' alone unless every declarator is unused, and never '
                    'touches doc-only findings. Run ',
                  ),
                  code([Component.text('dart format')]),
                  Component.text(' afterwards and review the diff.'),
                ]),
                const h3([
                  Component.text('Report-only: removal would not compile'),
                ]),
                ul(classes: 'checklist', [
                  for (final item in _reportOnly) li(rich(item)),
                ]),
              ],
            ),
            DocSection(
              id: 'skips',
              heading: 'What it skips, and what it cannot see',
              children: [
                const p([
                  Component.text(
                    'Each default skip is a known false-positive source; the '
                    'flag opts back in at that cost.',
                  ),
                ]),
                div(classes: 'table-wrap', [
                  table(classes: 'table', [
                    const thead([
                      tr([
                        th(
                          attributes: {'scope': 'col'},
                          [Component.text('Skipped')],
                        ),
                        th(
                          attributes: {'scope': 'col'},
                          [Component.text('Why')],
                        ),
                        th(
                          attributes: {'scope': 'col'},
                          [Component.text('Flag')],
                        ),
                      ]),
                    ]),
                    tbody([
                      for (final (what, why, flag) in _skips)
                        tr([
                          th(
                            attributes: const {'scope': 'row'},
                            [
                              code([Component.text(what)]),
                            ],
                          ),
                          td(rich(why)),
                          td(
                            attributes: const {'data-label': 'Opt back in'},
                            [
                              if (flag != null)
                                code(classes: 'flag', [Component.text(flag)])
                              else
                                const span(classes: 'muted', [
                                  Component.text('—'),
                                ]),
                            ],
                          ),
                        ]),
                    ]),
                  ]),
                ]),
                const h3([Component.text('Doc-only findings')]),
                const p([
                  Component.text(
                    'A dartdoc link counts as a reference to the analysis '
                    'server, but a comment is not a call. Declarations with no '
                    'code references are listed separately, never count toward '
                    'the exit code and are never removed.',
                  ),
                ]),
                const CodeBlock(
                  code: _docOnly,
                  language: Language.console,
                  copyText: '',
                ),
                const h3([Component.text('Limitations')]),
                ul(classes: 'checklist', [
                  li(
                    rich(
                      'A library package’s public API is legitimately unused '
                      'from the inside: prefer `--no-public` there.',
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
                      'Entry points other than `main` need excluding or '
                      "`@pragma('vm:entry-point')`.",
                    ),
                  ),
                  li(
                    rich(
                      'A package that does not analyze cleanly yields '
                      'incomplete references.',
                    ),
                  ),
                ]),
              ],
            ),
            const DocSection(
              id: 'library',
              heading: 'Library API',
              children: [
                p([
                  Component.text('The finder behind the CLI is exported from '),
                  code([Component.text('package:ciach/ciach.dart')]),
                  Component.text(
                    '. Options mirror the flags; the result carries every '
                    'finding with file, line, kind and qualified name, and '
                    'doc-only findings in their own list.',
                  ),
                ]),
                CodeBlock(
                  code: _library,
                  language: Language.dart,
                  title: 'tool/dead_code.dart',
                ),
              ],
            ),
            const DocSection(id: 'faq', heading: 'FAQ', children: [Faq()]),
          ]),
        ]),
      ],
    );
  }
}
