import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/docs_toc.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/pages/docs/ci.dart';
import 'package:ciach_website/pages/docs/compared.dart';
import 'package:ciach_website/pages/docs/config.dart';
import 'package:ciach_website/pages/docs/install.dart';
import 'package:ciach_website/pages/docs/library.dart';
import 'package:ciach_website/pages/docs/limitations.dart';
import 'package:ciach_website/pages/docs/options.dart';
import 'package:ciach_website/pages/docs/packages.dart';
import 'package:ciach_website/pages/docs/performance.dart';
import 'package:ciach_website/pages/docs/removing.dart';
import 'package:ciach_website/pages/docs/report.dart';
import 'package:ciach_website/pages/docs/running.dart';
import 'package:ciach_website/pages/docs/skips.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'docs_page.scopes.dart';

const _toc = [
  ('install', 'Install'),
  ('running', 'Running ciach'),
  ('report', 'The report'),
  ('skips', 'Skips'),
  ('removing', 'Removing'),
  ('options', 'Options'),
  ('config', 'Configuration'),
  ('packages', 'Packages and monorepos'),
  ('ci', 'CI'),
  ('compared', 'vs. the analyzer'),
  ('limitations', 'Limitations'),
  ('performance', 'Performance'),
  ('library', 'Library API'),
  ('faq', 'FAQ'),
];

/// Everything past the landing page, on one page with a sticky table of
/// contents: the reference that README.md points to. Each section is a file
/// under `docs/`, and the tables are styled by [DocsTable].
@scopedCss
class const DocsPage({required final String version, super.key})
    extends StatelessComponent {
  static const _class = _$DocsPageScope;

  static final _docs = _class('docs');
  static final _nav = _class('nav');
  static final _navFoot = _class('nav-foot');
  static final _body = _class('body');
  static final _head = _class('head');

  @css
  static List<StyleRule> get styles => [
    css(_docs.selector, [
      css('&').styles(
        display: .grid,
        padding: const .only(
          top: .expression('clamp(2.5rem, 6vw, 4.5rem)'),
          bottom: .expression('clamp(3rem, 8vw, 6rem)'),
        ),
        gap: .all(2.5.rem),
      ),
      shrinkableChildren(),
      css.media(_wide, [
        css('&').styles(
          gridTemplate: .new(
            columns: .new([
              .new(.new(220.px)),
              const .new(.minmax(.new(.zero), .fr(1))),
            ]),
          ),
        ),
      ]),
    ]),
    // The table of contents: a sticky column beside the text on wide screens,
    // a compact chip row above it on narrow ones.
    css(_nav.selector, [
      css('& ul', [
        css('&').styles(
          display: .grid,
          border: .only(left: hairlineSide(borderColor)),
          gap: .all(0.15.rem),
        ),
        css.media(_narrow, [
          css('&').styles(
            display: .flex,
            border: const .only(left: .none()),
            flexWrap: .wrap,
            gap: .all(0.4.rem),
          ),
        ]),
      ]),
      css('& li a', [
        css('&').styles(
          display: .block,
          padding: .symmetric(vertical: 0.4.rem, horizontal: 0.9.rem),
          margin: .only(left: (-1).px),
          border: .only(
            left: .new(color: const .new('transparent'), width: 2.px),
          ),
          color: text2Color,
          fontSize: 0.95.rem,
        ),
        css('&:hover, &${DocsToc.active.selector}').styles(
          border: .only(
            left: .new(color: accentColor, width: 2.px),
          ),
          color: textColor,
        ),
        css.media(_narrow, [
          css('&').styles(
            padding: .symmetric(vertical: 0.35.rem, horizontal: 0.75.rem),
            margin: .zero,
            border: hairline(border2Color),
            radius: .circular(999.px),
            fontSize: 0.85.rem,
          ),
          css('&:hover, &${DocsToc.active.selector}')
              .styles(border: hairline(accentColor)),
        ]),
      ]),
      css.media(_wide, [
        css('&').styles(
          position: const .sticky(
            top: .expression('calc(var(--header-h) + 2rem)'),
          ),
          alignSelf: .start,
        ),
      ]),
      css.media(_narrow, [
        css('& ${Prose.eyebrow.selector}').styles(display: .none),
      ]),
    ]),
    css(_navFoot.selector, [
      css('&').styles(
        margin: .only(top: 1.25.rem),
        fontSize: 0.9.rem,
      ),
      css('& a').styles(
        color: accentColor,
        textDecoration: underlined,
        raw: {'text-underline-offset': '0.15em'},
      ),
      css.media(_narrow, [css('&').styles(display: .none)]),
    ]),
    css(_body.selector).styles(maxWidth: 52.rem),
    css(_head.selector, [
      css('& h1').styles(
        fontSize: const .expression('clamp(2.2rem, 4vw, 3rem)'),
        fontWeight: .w700,
        letterSpacing: (-0.03).em,
      ),
      css('& ${Prose.lead.selector}').styles(margin: .only(top: 1.rem)),
    ]),
  ];

  /// Where the table of contents sits beside the text, and where it moves
  /// above it.
  static final _wide = MediaQuery.all(minWidth: 960.px);
  static final _narrow = MediaQuery.all(maxWidth: 959.px);

  @override
  Component build(BuildContext context) {
    return PageShell(
      page: .docs,
      version: version,
      children: [
        pageHead(
          title: 'Docs — $siteName',
          description:
              'How to install, configure and run ciach, how to read its '
              'report, what it skips and why, how --remove stays safe, the '
              'library API and answers to common questions.',
          path: 'docs',
          structuredData: [faqStructuredData()],
        ),
        div(classes: (Utility.container + _docs).name, [
          nav(
            classes: _nav.name,
            attributes: const {'aria-label': 'On this page'},
            [
              p(classes: Prose.eyebrow.name, const [.text('Docs')]),
              DocsToc(
                path: '/docs',
                ids: [for (final (id, _) in _toc) id],
                labels: [for (final (_, label) in _toc) label],
              ),
              p(classes: _navFoot.name, [
                externalLink(readmeUrl, [const .text('README on GitHub →')]),
              ]),
            ],
          ),
          div(classes: _body.name, [
            header(classes: _head.name, [
              const h1([.text('Docs')]),
              p(classes: Prose.lead.name, const [
                .text(
                  'Install, configure and run ciach, and read its findings with confidence.',
                ),
              ]),
            ]),
            installSection(),
            runningSection(),
            reportSection(),
            skipsSection(),
            removingSection(),
            optionsSection(),
            configSection(),
            packagesSection(),
            ciSection(),
            comparedSection(),
            limitationsSection(),
            performanceSection(),
            librarySection(),
            const DocSection(id: 'faq', heading: 'FAQ', children: [Faq()]),
          ]),
        ]),
      ],
    );
  }
}
