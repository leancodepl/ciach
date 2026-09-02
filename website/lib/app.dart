import 'package:ciach_website/components/ci_section.dart';
import 'package:ciach_website/components/ciach_demo.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/features.dart';
import 'package:ciach_website/components/footer.dart';
import 'package:ciach_website/components/formats.dart';
import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/how_it_works.dart';
import 'package:ciach_website/components/library_section.dart';
import 'package:ciach_website/components/nav_bar.dart';
import 'package:ciach_website/components/safety.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The landing page. Rendered once on the server into static HTML; only
/// `CopyButton` islands hydrate on the client.
class App extends StatelessComponent {
  const App({required this.version, super.key});

  /// The ciach version shown in the hero and footer.
  final String version;

  @override
  Component build(BuildContext context) {
    return Component.fragment([
      const a(href: '#main', classes: 'skip-link', [
        Component.text('Skip to content'),
      ]),
      const NavBar(),
      Component.element(
        tag: 'main',
        id: 'main',
        children: [
          Hero(version: version),
          const CiachDemo(),
          const Features(),
          const HowItWorks(),
          const OutputFormats(),
          const CiSection(),
          const Safety(),
          const LibrarySection(),
          const Faq(),
        ],
      ),
      SiteFooter(version: version),
    ]);
  }
}
