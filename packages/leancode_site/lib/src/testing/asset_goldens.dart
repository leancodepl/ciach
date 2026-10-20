/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The golden test for the generated assets in a site's `web/`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:jaspr/server.dart';
import 'package:leancode_site/src/components/og_card.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:leancode_site/src/testing/asset_renderer.dart';
import 'package:leancode_site/src/testing/pixel_compare.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Renders an asset with an [AssetRenderer].
typedef AssetRender = Future<Uint8List> Function(AssetRenderer renderer);

/// Share of pixels that may differ before an asset fails.
const maxDifferingShare = 0.005;

/// Whether the tests rewrite the committed files instead of comparing.
final updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// The icon set browsers, crawlers and home screens look for, rendered from
/// [favicon], the site's SVG drawn at a size in pixels with a corner radius
/// in its 64-unit viewBox: a legacy `.ico` at the root, a PNG tab icon for
/// browsers without SVG favicons, the iOS touch icon, and the two manifest
/// sizes. Together with `favicon.svg` among the text assets they are the
/// whole set.
Map<String, AssetRender> iconAssets(
  String Function({required int size, required int radius}) favicon,
) {
  Future<Uint8List> icon(
    AssetRenderer render, {
    required int size,
    required int radius,
    bool transparent = false,
  }) => render.icon(
    svg: favicon(size: size, radius: radius),
    size: size,
    transparent: transparent,
  );
  return {
    // Rounded with transparent corners for browser tabs.
    'favicon.ico': (render) async => img.encodeIco(
      img.decodePng(
        await icon(render, size: 32, radius: 14, transparent: true),
      )!,
    ),
    'favicon.png': (render) =>
        icon(render, size: 96, radius: 14, transparent: true),
    // Full-bleed for iOS and Android, which mask the corners themselves. The
    // mark sits within the inner 80%, so the manifest icons pass as maskable.
    'apple-touch-icon.png': (render) => icon(render, size: 180, radius: 0),
    'icon-192.png': (render) => icon(render, size: 192, radius: 0),
    'icon-512.png': (render) => icon(render, size: 512, radius: 0),
  };
}

/// The social card, rendered at its own size.
AssetRender ogCardAsset(OgCard card) =>
    (render) =>
        render.component(card, width: OgCard.width, height: OgCard.height);

/// Registers one test per asset. [textAssets] are written from their Dart
/// source and compared byte for byte; [assets] are rendered again in a pinned
/// Chrome for Testing and compared with the committed files. Both maps are
/// keyed by the path under `web/`. So `web/` cannot drift from the palette,
/// the site's mark, the `OgCard` component or the styles it is built with.
///
///     dart test                    # compare with the committed files
///     UPDATE_GOLDENS=1 dart test   # rewrite them after an intended change
///
/// Chrome for Testing is downloaded into `.dart_tool/puppeteer` on first run.
/// Small antialiasing differences are tolerated, a changed layout, color or
/// font is not.
void assetGoldenTests({
  required ServerOptions options,
  required SiteConfig site,
  required Map<String, String> textAssets,
  required Map<String, AssetRender> assets,
}) {
  late AssetRenderer renderer;

  setUpAll(() async {
    renderer = await .launch(options: options, site: site);
  });

  tearDownAll(() => renderer.close());

  for (final MapEntry(key: asset, value: content) in textAssets.entries) {
    test(asset, () {
      final file = File(p.join('web', asset));
      if (updateGoldens) {
        file.writeAsStringSync(content);
        printOnFailure('Rewrote ${file.path}');
        return;
      }
      expect(
        file.readAsStringSync(),
        content,
        reason:
            '${file.path} differs from its Dart source. If the change is '
            'intended, run `UPDATE_GOLDENS=1 dart test` and commit the result.',
      );
    });
  }

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
        final keep = Directory.systemTemp.createTempSync('site-assets-diff-');
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
