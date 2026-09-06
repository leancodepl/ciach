import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class SiteFooter extends StatelessComponent {
  const SiteFooter({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return footer(classes: 'site-footer', [
      section(
        classes: 'cta',
        attributes: const {'aria-labelledby': 'cta-heading'},
        [
          div(classes: 'container cta-inner', [
            const h2(id: 'cta-heading', [
              .text('Ready to make the first cut?'),
            ]),
            div(classes: 'hero-actions center', [
              externalLink(pubUrl, classes: 'button button-primary', [
                const .text('Get it on pub.dev'),
                Icon.external.build(size: 18),
              ]),
              a(href: '/docs', classes: 'button button-secondary', [
                Icon.book.build(size: 18),
                const .text('Read the docs'),
              ]),
            ]),
          ]),
        ],
      ),
      div(classes: 'container footer-grid', [
        div(classes: 'footer-brand', [
          logo(),
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
