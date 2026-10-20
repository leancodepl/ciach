/// Golden test for the generated assets in `web/`: the icons, the social card,
/// `favicon.svg` and the web manifest, compared with the committed files by
/// `package:leancode_site/testing.dart`, so `web/` cannot drift from the
/// palette, the ciach mark, the social card or the styles it is built with.
///
///     dart test                    # compare with the committed files
///     UPDATE_GOLDENS=1 dart test   # rewrite them after an intended change
@Timeout(Duration(minutes: 5))
library;

import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/main.server.options.dart';
import 'package:ciach_website/site.dart';
import 'package:leancode_site/leancode_site.dart';
import 'package:leancode_site/server.dart';
import 'package:leancode_site/testing.dart';
import 'package:test/test.dart';

void main() {
  final site = siteConfig(versionFromPubspec('ciach'));
  assetGoldenTests(
    options: defaultServerOptions,
    site: site,
    textAssets: {
      'favicon.svg': '${ciachFavicon()}\n',
      'site.webmanifest': webManifest(
        site,
        shortDescription: 'Finds and removes unused declarations in Dart and Flutter packages.',
      ),
    },
    assets: {
      ...iconAssets(ciachFavicon),
      'images/og.png': ogCardAsset(
        .new(heading: heroHeading, lead: heroLead, badges: heroBadges),
      ),
    },
  );
}
