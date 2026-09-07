/// Rasterizes the site's assets: SVG marks and Jaspr components, drawn by a
/// pinned Chrome for Testing so every machine produces the same pixels.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ciach_website/main.server.options.dart';
import 'package:ciach_website/seo.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

/// A headless browser that renders assets at exact pixel sizes.
class AssetRenderer {
  AssetRenderer._(this._browser, this._work);

  /// The Chrome for Testing build every render uses. A different build can
  /// antialias differently, so bump it and regenerate the assets together.
  static const chromeVersion = '152.0.7977.42';

  final Browser _browser;
  final Directory _work;

  /// Downloads [chromeVersion] into `.dart_tool/puppeteer` if needed and
  /// launches it. Also initializes Jaspr, so components render with the site's
  /// own styles.
  static Future<AssetRenderer> launch() async {
    Jaspr.initializeApp(options: defaultServerOptions);
    final chrome = await downloadChrome(version: chromeVersion);
    final browser = await puppeteer.launch(
      executablePath: chrome.executablePath,
      noSandboxFlag: true,
    );
    return AssetRenderer._(
      browser,
      Directory.systemTemp.createTempSync('ciach-assets-'),
    );
  }

  Future<void> close() async {
    await _browser.close();
    _work.deleteSync(recursive: true);
  }

  /// The mark of `web/favicon.svg` on a square with rounded corners of
  /// [radius] (in the SVG's 64-unit space), rendered at [size] pixels. With
  /// [transparent], the corners are see-through and the PNG keeps its alpha.
  Future<Uint8List> icon({
    required int size,
    required int radius,
    bool transparent = false,
  }) {
    final svg = File('web/favicon.svg').readAsStringSync();
    final mark = RegExp(r'<g[\s\S]*</g>').firstMatch(svg)![0]!;
    return _shoot(
      width: size,
      height: size,
      transparent: transparent,
      html:
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
          'width="$size" height="$size" style="display:block">'
          '<rect width="64" height="64" rx="$radius" fill="#050505"/>$mark</svg>',
    );
  }

  /// Renders [component] through Jaspr, with the site's stylesheet and web
  /// fonts, and screenshots the top-left [width]×[height] pixels. Every family
  /// in [fonts] must have loaded, or the render fails.
  Future<Uint8List> component(
    Component component, {
    required int width,
    required int height,
    List<String> fonts = const [],
  }) async {
    final fontFaces = _fetchFonts();
    // Jaspr inlines the site's own rules into the head.
    final response = await renderComponent(
      Document(
        lang: 'en',
        head: [RawText('<style>$fontFaces</style>')],
        body: component,
      ),
    );
    final html = File(p.join(_work.path, 'component.html'))
      ..writeAsBytesSync(response.body);

    final page = await _browser.newPage();
    try {
      await page.setViewport(DeviceViewport(width: width, height: height));
      await page.goto(html.absolute.uri.toString(), wait: Until.load);
      await page.evaluate<void>('() => document.fonts.ready');
      // document.fonts.check() is vacuously true when no face matches, so look
      // at the faces themselves: every family must be present and loaded.
      final loaded = await page.evaluate<List<Object?>>(
        '() => [...document.fonts]'
        '.filter((f) => f.status === "loaded")'
        '.map((f) => f.family.replace(/"/g, ""))',
      );
      for (final family in fonts) {
        if (!loaded.contains(family)) {
          throw StateError(
            'Web font not loaded: $family (loaded: ${loaded.join(', ')})',
          );
        }
      }
      return await page.screenshot(clip: math.Rectangle(0, 0, width, height));
    } finally {
      await page.close();
    }
  }

  /// Screenshots [html] at [width]×[height]. With [transparent], the page has
  /// no background and the PNG keeps its alpha channel.
  Future<Uint8List> _shoot({
    required String html,
    required int width,
    required int height,
    bool transparent = false,
  }) async {
    final page = await _browser.newPage();
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

  /// Downloads the site's Google Fonts stylesheet and the font files it names
  /// into the work directory, and returns the stylesheet rewritten to point at
  /// the local files. Chrome may not be able to reach Google Fonts (a proxy, a
  /// sandbox); curl honours the usual proxy settings.
  String _fetchFonts() {
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
      final file = File(p.join(_work.path, 'font-${count++}.woff2'))
        ..writeAsBytesSync(curl(m[1]!).codeUnits);
      return 'url(${file.absolute.uri})';
    });
    if (count == 0) {
      throw StateError('No font files found in the Google Fonts stylesheet');
    }
    return local;
  }
}
