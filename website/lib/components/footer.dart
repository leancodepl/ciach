import 'package:ciach_website/components/button.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class SiteFooter extends StatelessComponent {
  const SiteFooter({required this.version, super.key});

  final String version;

  @css
  static List<StyleRule> get styles => [
    css('.site-footer').styles(
      border: .only(top: hairlineSide(borderColor)),
      backgroundColor: bg2Color,
    ),
    css('.cta').styles(
      padding: const .symmetric(
        vertical: .expression('clamp(4rem, 8vw, 6rem)'),
        horizontal: .zero,
      ),
      border: .only(bottom: hairlineSide(borderColor)),
      raw: {
        'background':
            'radial-gradient(50% 60% at 50% 100%, rgba(237, 255, 47, 0.12), '
            'transparent 70%), var(--bg-2)',
      },
    ),
    css('.cta-inner').styles(maxWidth: 40.rem, textAlign: .center),
    css('.cta h2')
        .styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
    css('.cta p').styles(
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 1.1.rem,
    ),
    css('.footer-grid').styles(
      display: .grid,
      padding: .symmetric(vertical: 3.5.rem, horizontal: .zero),
      gap: .all(2.5.rem),
    ),
    css('.footer-grid h3').styles(
      margin: .only(bottom: 0.9.rem),
      color: mutedColor,
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      fontWeight: .w600,
      textTransform: .upperCase,
      letterSpacing: 0.08.em,
    ),
    css('.footer-grid ul').styles(display: .grid, gap: .all(0.5.rem)),
    css('.footer-grid li a').styles(color: text2Color),
    css('.footer-grid li a:hover').styles(color: accentColor),
    css('.footer-brand p').styles(
      maxWidth: 24.rem,
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 0.95.rem,
    ),
    css('.footer-bottom').styles(
      display: .flex,
      padding: .only(top: 1.5.rem, bottom: 2.rem),
      border: .only(top: hairlineSide(borderColor)),
      flexWrap: .wrap,
      justifyContent: .spaceBetween,
      gap: .all(0.75.rem),
      color: mutedColor,
      fontSize: 0.85.rem,
    ),
    css('.footer-bottom a, .footer-brand p a').styles(
      color: text2Color,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
    css.media(MediaQuery.all(minWidth: 760.px), [
      css('.footer-grid').styles(raw: {'grid-template-columns': '1fr 1fr'}),
    ]),
    css.media(MediaQuery.all(minWidth: 1000.px), [
      css('.footer-grid')
          .styles(raw: {'grid-template-columns': '1.6fr 1fr 1fr 1.4fr'}),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return footer(classes: 'site-footer', [
      section(
        classes: 'cta',
        attributes: const {'aria-labelledby': 'cta-heading'},
        [
          div(classes: 'container cta-inner', [
            const h2(id: 'cta-heading', [
              .text('Ready to make the first ciach?'),
            ]),
            div(classes: 'hero-actions center', [
              Button(href: pubUrl, external: true, [
                const .text('Get it on pub.dev'),
                Icon.external.build(size: 18),
              ]),
              Button(href: '/docs', variant: .secondary, [
                Icon.book.build(size: 18),
                const .text('Read the docs'),
              ]),
            ]),
          ]),
        ],
      ),
      div(classes: 'container footer-grid', [
        div(classes: 'footer-brand', [
          logo(id: 'footer-logo'),
          p([
            const .text('Dead code detector for Dart and Flutter. '),
            externalLink(changelogUrl, [.text('v$version')]),
            const .text(', Apache-2.0.'),
          ]),
        ]),
        nav(
          attributes: const {'aria-label': 'Project'},
          [
            const h3([.text('Project')]),
            ul([
              li([
                externalLink(pubUrl, [const .text('pub.dev')]),
              ]),
              li([
                externalLink(repoUrl, [const .text('GitHub')]),
              ]),
              li([
                externalLink(changelogUrl, [const .text('Changelog')]),
              ]),
              li([
                externalLink(issuesUrl, [const .text('Issues')]),
              ]),
            ]),
          ],
        ),
        const nav(
          attributes: {'aria-label': 'Docs'},
          [
            h3([.text('Docs')]),
            ul([
              li([
                a(href: '/docs#install', [.text('Install')]),
              ]),
              li([
                a(href: '/docs#ci', [.text('CI setup')]),
              ]),
              li([
                a(href: '/docs#config', [.text('Configuration')]),
              ]),
              li([
                a(href: '/docs#faq', [.text('FAQ')]),
              ]),
            ]),
          ],
        ),
        nav(
          attributes: const {'aria-label': 'LeanCode'},
          [
            const h3([.text('LeanCode')]),
            ul([
              li([
                externalLink(leancodeUrl, [const .text('leancode.co')]),
              ]),
              li([
                externalLink(patrolUrl, [const .text('Patrol')]),
              ]),
              li([
                externalLink(leancodePackagesUrl, [
                  const .text('More packages'),
                ]),
              ]),
              li([
                externalLink(leancodeEstimateUrl, [
                  const .text('Hire our team'),
                ]),
              ]),
            ]),
          ],
        ),
      ]),
      div(classes: 'container footer-bottom', [
        p([
          const .text('© 2026 '),
          externalLink(leancodeUrl, [const .text('LeanCode')]),
          const .text('. Apache License 2.0.'),
        ]),
        p([
          const .text('Built with '),
          externalLink('https://jaspr.site', [const .text('Jaspr')]),
          const .text('.'),
        ]),
      ]),
    ]);
  }
}
