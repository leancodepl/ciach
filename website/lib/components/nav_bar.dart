import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class NavBar extends StatelessComponent {
  const NavBar({super.key});

  static const _links = [
    ('#features', 'Features'),
    ('#how-it-works', 'How it works'),
    ('#ci', 'CI'),
    ('#safety', 'Safety'),
    ('#faq', 'FAQ'),
  ];

  @override
  Component build(BuildContext context) {
    return header(classes: 'site-header', [
      nav(
        classes: 'container nav',
        attributes: const {'aria-label': 'Primary'},
        [
          a(
            href: '#top',
            classes: 'brand',
            attributes: const {'aria-label': 'ciach home'},
            [logo()],
          ),
          ul(classes: 'nav-links', [
            for (final (href, label) in _links)
              li([
                a(href: href, [Component.text(label)]),
              ]),
          ]),
          div(classes: 'nav-actions', [
            externalLink(pubUrl, classes: 'button button-ghost', [
              const Component.text('pub.dev'),
            ]),
            externalLink(
              repoUrl,
              classes: 'button button-ghost button-icon',
              label: 'ciach on GitHub',
              [
                Icon.github.build(size: 18),
                const span(classes: 'hide-sm', [Component.text('GitHub')]),
              ],
            ),
          ]),
        ],
      ),
    ]);
  }
}
