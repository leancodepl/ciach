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
            const p([
              Component.text(
                'Install ciach, run it on a package, and see what has been '
                'quietly rotting in there.',
              ),
            ]),
            div(classes: 'hero-actions center', [
              externalLink(pubUrl, classes: 'button button-primary', [
                const Component.text('Get it on pub.dev'),
                Icon.external.build(size: 18),
              ]),
              externalLink(readmeUrl, classes: 'button button-secondary', [
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
          const p([
            Component.text(
              'Dead code detector for Dart and Flutter. Apache-2.0 licensed, '
              'open source, built by LeanCode.',
            ),
          ]),
          p(classes: 'footer-version', [
            const Component.text('Latest release: '),
            externalLink(changelogUrl, [Component.text('v$version')]),
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
              li([
                externalLink(exampleUrl, [
                  const Component.text('Example package'),
                ]),
              ]),
              li([
                externalLink(licenseUrl, [const Component.text('License')]),
              ]),
            ]),
          ],
        ),
        const nav(
          attributes: {'aria-label': 'On this page'},
          [
            h3([Component.text('On this page')]),
            ul([
              li([
                a(href: '#features', [Component.text('Features')]),
              ]),
              li([
                a(href: '#how-it-works', [Component.text('How it works')]),
              ]),
              li([
                a(href: '#formats', [Component.text('Output formats')]),
              ]),
              li([
                a(href: '#ci', [Component.text('CI setup')]),
              ]),
              li([
                a(href: '#safety', [Component.text('Safety')]),
              ]),
              li([
                a(href: '#faq', [Component.text('FAQ')]),
              ]),
            ]),
          ],
        ),
        div(classes: 'footer-leancode', [
          const h3([Component.text('Maintained by LeanCode')]),
          const p([
            Component.text(
              'We are top-tier experts focused on Flutter enterprise solutions, '
              'creators of Patrol, and we run ciach across our own codebases.',
            ),
          ]),
          ul([
            li([
              externalLink(leancodeUrl, [const Component.text('leancode.co')]),
            ]),
            li([
              externalLink(patrolUrl, [
                const Component.text('Patrol — Flutter UI testing'),
              ]),
            ]),
            li([
              externalLink(leancodePackagesUrl, [
                const Component.text('More LeanCode packages'),
              ]),
            ]),
            li([
              externalLink(leancodeEstimateUrl, [
                const Component.text('Hire our team'),
              ]),
            ]),
          ]),
        ]),
      ]),
      div(classes: 'container footer-bottom', [
        p([
          const Component.text('© 2026 '),
          externalLink(leancodeUrl, [const Component.text('LeanCode')]),
          const Component.text(
            '. ciach is released under the Apache License 2.0.',
          ),
        ]),
        p([
          const Component.text('Built with '),
          externalLink('https://jaspr.site', [const Component.text('Jaspr')]),
          const Component.text(', pre-rendered to static HTML.'),
        ]),
      ]),
    ]);
  }
}
