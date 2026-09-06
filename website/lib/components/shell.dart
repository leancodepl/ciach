import 'package:ciach_website/components/footer.dart';
import 'package:ciach_website/components/nav_bar.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Which top-level page is being shown; drives the active nav item and the
/// page-relative anchors (a bare `#fragment` would resolve against the
/// document's `<base href>`).
enum SitePage(final String path) {
  home('/'),
  docs('/docs'),
}

/// Skip link, header, `<main>` and footer around a page's content.
class const PageShell({
  required final SitePage page,
  required final String version,
  required final List<Component> children,
  super.key,
}) extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return .fragment([
      a(href: '${page.path}#main', classes: 'skip-link', const [
        .text('Skip to content'),
      ]),
      NavBar(page: page),
      main_(id: 'main', children),
      SiteFooter(version: version),
    ]);
  }
}
