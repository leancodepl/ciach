import 'package:ciach_website/components/ciach_demo.dart';
import 'package:ciach_website/components/features.dart';
import 'package:ciach_website/components/formats.dart';
import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/jaspr.dart';

/// The landing page: what ciach is, what it looks like, where to go next.
class HomePage extends StatelessComponent {
  const HomePage({required this.version, super.key});

  final String version;

  @override
  Component build(BuildContext context) {
    return PageShell(
      page: SitePage.home,
      version: version,
      children: [
        pageHead(
          title: '$siteName — $tagline',
          description: description,
          path: '',
        ),
        Hero(version: version),
        const CiachDemo(),
        const Features(),
        const OutputFormats(),
      ],
    );
  }
}
