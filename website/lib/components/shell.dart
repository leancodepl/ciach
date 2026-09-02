import 'package:ciach_website/components/footer.dart';
import 'package:ciach_website/components/nav_bar.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Which top-level page is being shown; drives the active nav item.
enum SitePage { home, docs }

/// Skip link, header, `<main>` and footer around a page's content.
class PageShell extends StatelessComponent {
  const PageShell({
    required this.page,
    required this.version,
    required this.children,
    super.key,
  });

  final SitePage page;
  final String version;
  final List<Component> children;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      const a(href: '#main', classes: 'skip-link', [
        Component.text('Skip to content'),
      ]),
      NavBar(page: page),
      Component.element(tag: 'main', id: 'main', children: children),
      SiteFooter(version: version),
    ]);
  }
}
