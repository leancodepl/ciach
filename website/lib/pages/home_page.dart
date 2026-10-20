import 'package:ciach_website/components/ciach_demo.dart';
import 'package:ciach_website/components/features.dart';
import 'package:ciach_website/components/formats.dart';
import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/upstream_bugs.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/jaspr.dart';
import 'package:leancode_site/leancode_site.dart';

/// The landing page: what ciach is, what it looks like, where to go next.
class const HomePage({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return const PageShell(
      path: '/',
      footer: siteFooter,
      children: [
        PageHead(
          title: '$siteName — $tagline',
          description: description,
          path: '',
        ),
        CiachHero(),
        CiachDemo(),
        Features(),
        OutputFormats(),
        UpstreamBugs(),
      ],
    );
  }
}
