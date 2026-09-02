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
              Component.text('Ready to make the first cut?'),
            ]),
            div(classes: 'hero-actions center', [
              externalLink(pubUrl, classes: 'button button-primary', [
                const Component.text('Get it on pub.dev'),
                Icon.external.build(size: 18),
              ]),
              a(href: '/docs', classes: 'button button-secondary', [
                Icon.book.build(size: 18),
                const Component.text('Read the docs'),
              ]),
            ]),
          ]),
        ],
      ),
      div(classes: 'container footer-grid', [
        div(classes: 'footer-brand', [
          logo(),
          p([
            const Component.text('Dead code detector for Dart and Flutter. '),
            externalLink(changelogUrl, [Component.text('v$version')]),
            const Component.text(', Apache-2.0.'),
          ]),
        ]),
        nav(
          attributes: const {'aria-label': 'Project'},
          [
            const h3([Component.text('Project')]),
            ul([
              li([
                externalLink(pubUrl, [const Component.text('pub.dev')]),
              ]),
              li([
                externalLink(repoUrl, [const Component.text('GitHub')]),
              ]),
              li([
                externalLink(changelogUrl, [const Component.text('Changelog')]),
              ]),
              li([
                externalLink(issuesUrl, [const Component.text('Issues')]),
              ]),
            ]),
          ],
        ),
        const nav(
          attributes: {'aria-label': 'Docs'},
          [
            h3([Component.text('Docs')]),
            ul([
              li([
                a(href: '/docs#install', [Component.text('Install')]),
              ]),
              li([
                a(href: '/docs#ci', [Component.text('CI setup')]),
              ]),
              li([
                a(href: '/docs#config', [Component.text('Configuration')]),
              ]),
              li([
                a(href: '/docs#faq', [Component.text('FAQ')]),
              ]),
            ]),
          ],
        ),
        nav(
          attributes: const {'aria-label': 'LeanCode'},
          [
            const h3([Component.text('LeanCode')]),
            ul([
              li([
                externalLink(leancodeUrl, [
                  const Component.text('leancode.co'),
                ]),
              ]),
              li([
                externalLink(patrolUrl, [const Component.text('Patrol')]),
              ]),
              li([
                externalLink(leancodePackagesUrl, [
                  const Component.text('More packages'),
                ]),
              ]),
              li([
                externalLink(leancodeEstimateUrl, [
                  const Component.text('Hire our team'),
                ]),
              ]),
            ]),
          ],
        ),
      ]),
      div(classes: 'container footer-bottom', [
        p([
          const Component.text('© 2026 '),
          externalLink(leancodeUrl, [const Component.text('LeanCode')]),
          const Component.text('. Apache License 2.0.'),
        ]),
        p([
          const Component.text('Built with '),
          externalLink('https://jaspr.site', [const Component.text('Jaspr')]),
          const Component.text('.'),
        ]),
      ]),
    ]);
  }
}
