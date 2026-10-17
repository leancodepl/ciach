import 'package:ciach_website/pages/docs_page.dart';
import 'package:ciach_website/pages/home_page.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_router/jaspr_router.dart';

/// The site: a lean landing page and a docs page. Both routes are rendered to
/// static HTML at build time; only `CopyButton` islands hydrate on the client.
class const App({
  /// The ciach version shown across the site.
  required final String version,
  super.key,
}) extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return Router(
      routes: [
        Route(
          path: '/',
          builder: (context, state) => HomePage(version: version),
        ),
        Route(
          path: '/docs',
          builder: (context, state) => DocsPage(version: version),
        ),
      ],
    );
  }
}
