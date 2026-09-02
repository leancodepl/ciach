import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class NavBar extends StatelessComponent {
  const NavBar({required this.page, super.key});

  final SitePage page;

  @override
  Component build(BuildContext context) {
    final onHome = page == SitePage.home;
    return header(classes: 'site-header', [
      nav(
        classes: 'container nav',
        attributes: const {'aria-label': 'Primary'},
        [
          a(
            href: '/',
            classes: 'brand',
            attributes: const {'aria-label': 'ciach home'},
            [logo()],
          ),
          ul(classes: 'nav-links', [
            li(classes: 'hide-md', [
              a(href: onHome ? '#features' : '/#features', const [
                Component.text('Features'),
              ]),
            ]),
            li(classes: 'hide-md', [
              a(href: onHome ? '#formats' : '/#formats', const [
                Component.text('Output'),
              ]),
            ]),
            li([
              a(
                href: '/docs',
                classes: onHome ? null : 'is-active',
                attributes: onHome ? null : const {'aria-current': 'page'},
                const [Component.text('Docs')],
              ),
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
