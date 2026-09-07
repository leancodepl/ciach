/// Golden test for the rendered image assets in `web/`: the icons and the
/// social card. Each asset is rendered again in a pinned Chrome for Testing and
/// compared with the committed file, so `web/` cannot drift from
/// `favicon.svg`, the `OgCard` component or the styles it is built with.
///
///     dart test                    # compare with the committed files
///     UPDATE_GOLDENS=1 dart test   # rewrite them after an intended change
///
/// Chrome for Testing is downloaded into `.dart_tool/puppeteer` on first run.
/// The social card needs `curl` and access to Google Fonts. Small antialiasing
/// differences are tolerated, a changed layout, colour or font is not.
///
/// This file says what the assets are; `support/asset_renderer.dart` draws
/// them and `support/pixel_compare.dart` judges the result.
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:ciach_website/components/og_card.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/asset_renderer.dart';
import 'support/pixel_compare.dart';

/// Share of pixels that may differ before an asset fails.
const maxDifferingShare = 0.005;

final updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// The files this test produces, relative to `web/`. Together with
/// `favicon.svg` they are the icon set browsers, crawlers and home screens
/// look for: a legacy `.ico` at the root, a PNG tab icon for browsers without
/// SVG favicons, the iOS touch icon, and the two manifest sizes.
final assets = <String, Future<Uint8List> Function(AssetRenderer)>{
  // Rounded with transparent corners for browser tabs.
  'favicon.ico': (render) async => img.encodeIco(
    img.decodePng(await render.icon(size: 32, radius: 14, transparent: true))!,
  ),
  'favicon.png': (render) =>
      render.icon(size: 96, radius: 14, transparent: true),
  // Full-bleed for iOS and Android, which mask the corners themselves. The
  // mark sits within the inner 80%, so the manifest icons pass as maskable.
  'apple-touch-icon.png': (render) => render.icon(size: 180, radius: 0),
  'icon-192.png': (render) => render.icon(size: 192, radius: 0),
  'icon-512.png': (render) => render.icon(size: 512, radius: 0),
  'images/og.png': (render) => render.component(
    const OgCard(),
    width: OgCard.width,
    height: OgCard.height,
    fonts: OgCard.fonts,
  ),
};

void main() {
  late AssetRenderer renderer;

  setUpAll(() async {
    renderer = await AssetRenderer.launch();
  });

  tearDownAll(() => renderer.close());

  for (final MapEntry(key: asset, value: render) in assets.entries) {
    test(asset, () async {
      final file = File(p.join('web', asset));
      final actual = await render(renderer);

      if (updateGoldens) {
        file.writeAsBytesSync(actual);
        printOnFailure('Rewrote ${file.path}');
        return;
      }

      final expected = img.decodeNamedImage(asset, file.readAsBytesSync())!;
      final rendered = img.decodeNamedImage(asset, actual)!;
      expect(
        (rendered.width, rendered.height),
        (expected.width, expected.height),
        reason: '${file.path} has a different size than the render',
      );

      final result = compare(expected, rendered);
      final share = result.differing / (expected.width * expected.height);
      if (share > maxDifferingShare) {
        final keep = Directory.systemTemp.createTempSync('ciach-assets-diff-');
        File(p.join(keep.path, p.basename(asset))).writeAsBytesSync(actual);
        File(p.join(keep.path, '${p.basenameWithoutExtension(asset)}.diff.png'))
            .writeAsBytesSync(img.encodePng(result.diff));
        fail(
          '${file.path}: ${result.differing} pixels differ '
          '(${(share * 100).toStringAsFixed(3)}%). The render and a diff are '
          'in ${keep.path}. If the change is intended, run '
          '`UPDATE_GOLDENS=1 dart test` and commit the result.',
        );
      }
    });
  }
}
