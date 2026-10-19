import 'package:ciach_website/content/docs_components.dart';
import 'package:ciach_website/content/docs_layout.dart';
import 'package:ciach_website/content/sections_extension.dart';
import 'package:ciach_website/pages/home_page.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/server.dart';
import 'package:jaspr_content/jaspr_content.dart' hide DocsLayout;
import 'package:jaspr_content/theme.dart';
import 'package:jaspr_router/jaspr_router.dart';

/// The site: a lean landing page, and the pages under `content/`, which
/// `jaspr_content` renders from Markdown in [DocsLayout]. Every route is
/// rendered to static HTML at build time; only `CopyButton` and the table of
/// contents hydrate on the client.
class const App({
  /// The ciach version shown across the site.
  required final String version,
  super.key,
}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => ContentApp.custom(
    loaders: [FilesystemLoader('content')],
    configResolver: PageConfig.all(
      parsers: const [MarkdownParser()],
      extensions: const [TableOfContentsExtension(), SectionsExtension()],
      components: const [DocsComponents()],
      layouts: [DocsLayout(version: version)],
      // The site brings its own styles.
      theme: const ContentTheme.none(),
    ),
    routerBuilder: (routes) => Document(
      lang: 'en',
      base: basePath,
      meta: siteMeta,
      head: siteHead(version: version),
      body: Router(
        routes: [
          Route(
            path: '/',
            builder: (context, state) => HomePage(version: version),
          ),
          ...routes.expand((routes) => routes),
        ],
      ),
    ),
  );
}
