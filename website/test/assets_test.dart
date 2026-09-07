/// Golden test for the rendered image assets in `web/`: the PNG icons and the
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
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ciach_website/components/og_card.dart';
import 'package:ciach_website/main.server.options.dart';
import 'package:ciach_website/seo.dart';
import 'package:image/image.dart' as img;
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

/// The Chrome for Testing build every render uses. A different build can
/// antialias differently, so bump it and regenerate the assets together.
const chromeVersion = '152.0.7977.42';

/// Share of pixels that may differ before an asset fails.
const maxDifferingShare = 0.005;

/// Per-pixel colour distance (in the YIQ space, on a 0–1 scale) below which
/// two pixels count as the same. 0.1 forgives antialiasing, not a new colour.
const colorThreshold = 0.1;

final updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

/// The files this test produces, relative to `web/`.
final assets = <String, Future<Uint8List> Function(Browser, Directory)>{
  // Rounded with transparent corners for browsers.
  'favicon.png': (browser, _) =>
      renderIcon(browser, size: 96, radius: 14, transparent: true),
  // Full-bleed for iOS, which masks the corners itself.
  'apple-touch-icon.png': (browser, _) =>
      renderIcon(browser, size: 180, radius: 0),
  'images/og.png': renderCard,
};

void main() {
  late Browser browser;
  late Directory work;

  setUpAll(() async {
    Jaspr.initializeApp(options: defaultServerOptions);
    work = Directory.systemTemp.createTempSync('ciach-assets-');
    final chrome = await downloadChrome(version: chromeVersion);
    browser = await puppeteer.launch(
      executablePath: chrome.executablePath,
      noSandboxFlag: true,
    );
  });

  tearDownAll(() async {
    await browser.close();
    work.deleteSync(recursive: true);
  });

  for (final MapEntry(key: asset, value: render) in assets.entries) {
    test(asset, () async {
      final file = File(p.join('web', asset));
      final actual = await render(browser, work);

      if (updateGoldens) {
        file.writeAsBytesSync(actual);
        printOnFailure('Rewrote ${file.path}');
        return;
      }

      final expected = img.decodePng(file.readAsBytesSync())!;
      final rendered = img.decodePng(actual)!;
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

/// Screenshots [html] at [width]×[height]. With [transparent], the page has
/// no background and the PNG keeps its alpha channel.
Future<Uint8List> shoot(
  Browser browser, {
  required String html,
  required int width,
  required int height,
  bool transparent = false,
}) async {
  final page = await browser.newPage();
  try {
    await page.setViewport(DeviceViewport(width: width, height: height));
    await page.setContent(
      '<!doctype html><style>html,body{margin:0;background:'
      '${transparent ? 'transparent' : '#050505'}}</style>$html',
    );
    return await page.screenshot(
      clip: math.Rectangle(0, 0, width, height),
      omitBackground: transparent,
    );
  } finally {
    await page.close();
  }
}

/// The favicon's mark on a square with rounded corners of [radius] (in the
/// SVG's 64-unit space), rendered at [size] pixels.
Future<Uint8List> renderIcon(
  Browser browser, {
  required int size,
  required int radius,
  bool transparent = false,
}) {
  final svg = File('web/favicon.svg').readAsStringSync();
  final mark = RegExp(r'<g[\s\S]*</g>').firstMatch(svg)![0]!;
  return shoot(
    browser,
    width: size,
    height: size,
    transparent: transparent,
    html:
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
        'width="$size" height="$size" style="display:block">'
        '<rect width="64" height="64" rx="$radius" fill="#050505"/>$mark</svg>',
  );
}

/// Renders [OgCard] through Jaspr with the site's stylesheet and web fonts.
Future<Uint8List> renderCard(Browser browser, Directory work) async {
  final fontFaces = fetchFonts(work);
  // Jaspr inlines the site's own rules into the head; the card brings its
  // sizing along.
  final response = await renderComponent(
    Document(
      lang: 'en',
      head: [RawText('<style>$fontFaces</style>')],
      body: const OgCard(),
    ),
  );
  final html = File(p.join(work.path, 'og.html'))
    ..writeAsBytesSync(response.body);

  final page = await browser.newPage();
  try {
    await page.setViewport(
      const DeviceViewport(width: OgCard.width, height: OgCard.height),
    );
    await page.goto(html.absolute.uri.toString(), wait: Until.load);
    await page.evaluate<void>('() => document.fonts.ready');
    // document.fonts.check() is vacuously true when no face matches, so look
    // at the faces themselves: every family must be present and loaded.
    final loaded = await page.evaluate<List<Object?>>(
      '() => [...document.fonts]'
      '.filter((f) => f.status === "loaded")'
      '.map((f) => f.family.replace(/"/g, ""))',
    );
    for (final family in OgCard.fonts) {
      expect(loaded, contains(family), reason: 'Web font not loaded: $family');
    }
    return await page.screenshot(
      clip: const math.Rectangle(0, 0, OgCard.width, OgCard.height),
    );
  } finally {
    await page.close();
  }
}

/// Downloads the site's Google Fonts stylesheet and the font files it names
/// into [dir], and returns the stylesheet rewritten to point at the local
/// files. Chrome may not be able to reach Google Fonts (a proxy, a sandbox);
/// curl honours the usual proxy settings.
String fetchFonts(Directory dir) {
  String curl(String url, [List<String> args = const []]) {
    final result = Process.runSync('curl', [
      '--fail',
      '--silent',
      '--show-error',
      '--location',
      ...args,
      url,
    ], stdoutEncoding: null);
    if (result.exitCode != 0) {
      throw StateError('curl $url failed: ${result.stderr}');
    }
    return String.fromCharCodes(result.stdout as List<int>);
  }

  // A modern UA makes Google Fonts answer with woff2 sources.
  const userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0 Safari/537.36';
  final css = curl(fontsStylesheetUrl, ['--user-agent', userAgent]);
  var count = 0;
  final local = css.replaceAllMapped(RegExp(r'url\((https:[^)]+)\)'), (m) {
    final file = File(p.join(dir.path, 'font-${count++}.woff2'))
      ..writeAsBytesSync(curl(m[1]!).codeUnits);
    return 'url(${file.absolute.uri})';
  });
  if (count == 0) {
    throw StateError('No font files found in the Google Fonts stylesheet');
  }
  return local;
}

/// Counts the pixels of [actual] that differ from [expected] beyond
/// [colorThreshold], and draws them in red on a faded copy of [expected].
({int differing, img.Image diff}) compare(
  img.Image expected,
  img.Image actual,
) {
  final diff = img.Image(width: expected.width, height: expected.height);
  const maxDelta = 35215 * colorThreshold * colorThreshold;
  var differing = 0;
  for (var y = 0; y < expected.height; y++) {
    for (var x = 0; x < expected.width; x++) {
      final a = _rgba(expected, x, y);
      final b = _rgba(actual, x, y);
      if (_colorDelta(a, b) > maxDelta) {
        differing++;
        diff.setPixelRgb(x, y, 255, 0, 0);
      } else {
        final gray = 255 - ((255 - _luma(a)) * 0.1).round();
        diff.setPixelRgb(x, y, gray, gray, gray);
      }
    }
  }
  return (differing: differing, diff: diff);
}

typedef _Rgba = (double, double, double, double);

_Rgba _rgba(img.Image image, int x, int y) {
  final pixel = image.getPixel(x, y);
  final alpha = image.numChannels == 4 ? pixel.a.toDouble() : 255.0;
  return (pixel.r.toDouble(), pixel.g.toDouble(), pixel.b.toDouble(), alpha);
}

// The colour metric of pixelmatch: both pixels are blended onto white and
// compared in the YIQ space, weighting luma over chroma.
double _colorDelta(_Rgba a, _Rgba b) {
  final (r1, g1, b1) = _blend(a);
  final (r2, g2, b2) = _blend(b);
  final y = _y(r1, g1, b1) - _y(r2, g2, b2);
  final i = _i(r1, g1, b1) - _i(r2, g2, b2);
  final q = _q(r1, g1, b1) - _q(r2, g2, b2);
  return 0.5053 * y * y + 0.299 * i * i + 0.1957 * q * q;
}

(double, double, double) _blend(_Rgba c) {
  final (r, g, b, a) = c;
  final alpha = a / 255;
  return (
    255 + (r - 255) * alpha,
    255 + (g - 255) * alpha,
    255 + (b - 255) * alpha,
  );
}

int _luma(_Rgba c) {
  final (r, g, b) = _blend(c);
  return _y(r, g, b).round();
}

double _y(double r, double g, double b) =>
    r * 0.29889531 + g * 0.58662247 + b * 0.11448223;
double _i(double r, double g, double b) =>
    r * 0.59597799 - g * 0.27417610 - b * 0.32180189;
double _q(double r, double g, double b) =>
    r * 0.21147017 - g * 0.52261711 + b * 0.31114694;
