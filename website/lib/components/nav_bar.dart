import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The site header: the brand on the left, and on the right the three places
/// a visitor can go from any page. Every item is a real link; in-page
/// sections are reached by scrolling.
class NavBar extends StatelessComponent {
  const NavBar({required this.page, super.key});

  final SitePage page;

  @override
  Component build(BuildContext context) {
    final onDocs = page == SitePage.docs;
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
            li([
              a(
                href: '/docs',
                classes: onDocs ? 'is-active' : null,
                attributes: onDocs ? const {'aria-current': 'page'} : null,
                [Icon.book.build(size: 18), const Component.text('Docs')],
              ),
            ]),
            li([
              externalLink(pubUrl, [
                Icon.external.build(size: 18),
                const Component.text('pub.dev'),
              ]),
            ]),
            li([
              externalLink(repoUrl, label: 'ciach on GitHub', [
                Icon.github.build(size: 18),
                const span(classes: 'hide-sm', [Component.text('GitHub')]),
              ]),
            ]),
          ]),
        ],
      ),
    ]);
  }
}
