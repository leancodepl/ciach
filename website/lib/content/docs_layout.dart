/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/docs_toc.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:jaspr_content/jaspr_content.dart';

part 'docs_layout.scopes.dart';

/// The docs page around its Markdown: the reference that README.md points
/// to, with a sticky table of contents built from the page's `h2` headings.
/// The page's title, lead and description come from its frontmatter.
@scopedCss
class const DocsLayout({
  /// The ciach version shown in the page shell.
  required final String version,
}) implements PageLayout {
  static const _class = _$DocsLayoutScope;

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
  Pattern get name => 'docs';

  @override
  Component buildLayout(Page page, Component child) {
    final (title, description, lead) = switch (page.data.page) {
      {
        'title': final String title,
        'description': final String description,
        'lead': final String lead,
      } =>
        (title, description, lead),
      _ => throw ArgumentError(
        '${page.path} needs a title, a description and a lead in its frontmatter.',
      ),
    };
    final entries = switch (page.data['toc']) {
      final TableOfContents toc => toc.entries,
      _ => const <TocEntry>[],
    };
    return PageShell(
      page: .docs,
      version: version,
      children: [
        pageHead(
          title: '$title — $siteName',
          description: description,
          path: page.url.substring(1),
          structuredData: [faqStructuredData()],
        ),
        div(classes: (Utility.container + _docs).name, [
          nav(
            classes: _nav.name,
            attributes: const {'aria-label': 'On this page'},
            [
              p(classes: Prose.eyebrow.name, [.text(title)]),
              DocsToc(
                path: page.url,
                ids: [for (final entry in entries) entry.id],
                labels: [for (final entry in entries) entry.text],
              ),
              p(classes: _navFoot.name, [
                externalLink(readmeUrl, [const .text('README on GitHub →')]),
              ]),
            ],
          ),
          div(classes: _body.name, [
            header(classes: _head.name, [
              h1([.text(title)]),
              p(classes: Prose.lead.name, [.text(lead)]),
            ]),
            child,
          ]),
        ]),
      ],
    );
  }
}
