/// Rasterizes a site's assets: SVG marks and Jaspr components, drawn by a
/// pinned Chrome for Testing so every machine produces the same pixels.
library;

import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:jaspr/dom.dart';
import 'package:jaspr/server.dart';
import 'package:leancode_site/src/fonts.dart';
import 'package:leancode_site/src/palette.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';

/// A headless browser that renders assets at exact pixel sizes.
///
/// Components are served over a loopback HTTP server rooted at the site's
/// `web/`, with the `packages/` paths of this package's fonts resolved to
/// the package, so relative URLs resolve as they do in production; `file://`
/// pages would refuse to load fonts from another directory.
class AssetRenderer {
  AssetRenderer._(this._browser, this._server, this._site);

  /// The Chrome for Testing build every render uses. A different build can
  /// antialias differently, so bump it and regenerate the assets together.
  static const chromeVersion = '152.0.7977.42';

  final Browser _browser;
  final HttpServer _server;
  final SiteConfig _site;

  /// The HTML the server answers `/component.html` with.
  Uint8List? _page;

  /// Downloads [chromeVersion] into `.dart_tool/puppeteer` if needed and
  /// launches it. Also initializes Jaspr with the site's [options], so
  /// components render with the site's own styles, and gives them [site].
  static Future<AssetRenderer> launch({
    required ServerOptions options,
    required SiteConfig site,
  }) async {
    Jaspr.initializeApp(options: options);
    final chrome = await downloadChrome(version: chromeVersion);
    final browser = await puppeteer.launch(
      executablePath: chrome.executablePath,
      noSandboxFlag: true,
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final renderer = AssetRenderer._(browser, server, site);
    server.listen(renderer._serve);
    return renderer;
  }

  Future<void> close() async {
    await _browser.close();
    await _server.close();
  }

  /// The favicon [svg] rendered at [size] pixels. With [transparent], the
  /// page has no background and the PNG keeps its alpha channel, so corners
  /// the SVG rounds are see-through.
  Future<Uint8List> icon({
    required String svg,
    required int size,
    bool transparent = false,
  }) => _shoot(width: size, height: size, transparent: transparent, html: svg);

  /// Renders [component] through Jaspr, with the site's styles and fonts, and
  /// screenshots the top-left [width]×[height] pixels. Every family in
  /// [fontFamilies] must have loaded, or the render fails.
  Future<Uint8List> component(
    Component component, {
    required int width,
    required int height,
  }) async {
    // Jaspr inlines the site's own rules into the head.
    final response = await renderComponent(
      Document(
        lang: 'en',
        head: [RawText('<style>$fontFaces</style>')],
        body: Site(config: _site, child: component),
      ),
    );
    _page = response.body;

    final page = await _browser.newPage();
    try {
      await page.setViewport(.new(width: width, height: height));
      await page.goto(
        'http://${_server.address.host}:${_server.port}/component.html',
        wait: .load,
      );
      await page.evaluate<void>('() => document.fonts.ready');
      // document.fonts.check() is vacuously true when no face matches, so look
      // at the faces themselves: every family must be present and loaded.
      final loaded = await page.evaluate<List<Object?>>(
        '() => [...document.fonts].filter((f) => f.status === "loaded").map((f) => f.family.replace(/"/g, ""))',
      );
      for (final family in fontFamilies) {
        if (!loaded.contains(family)) {
          throw StateError(
            'Web font not loaded: $family (loaded: ${loaded.join(', ')})',
          );
        }
      }
      return await page.screenshot(clip: .new(0, 0, width, height));
    } finally {
      await page.close();
    }
  }

  /// Answers `/component.html` with the last rendered page, `/packages/…`
  /// from the package that owns the path, and everything else from `web/`,
  /// like the deployed site does.
  Future<void> _serve(HttpRequest request) async {
    final response = request.response;
    final path = request.uri.path;
    if (path == '/component.html' && _page != null) {
      response.headers.contentType = .html;
      response.add(_page!);
    } else if (await _file(path) case final file?) {
      if (_contentTypes[p.extension(file.path)] case final type?) {
        response.headers.set(HttpHeaders.contentTypeHeader, type);
      }
      response.add(file.readAsBytesSync());
    } else {
      response.statusCode = HttpStatus.notFound;
    }
    await response.close();
  }

  /// The file behind [path], or null when there is none.
  Future<File?> _file(String path) async {
    final relative = p.normalize(path.substring(1));
    final File file;
    if (p.split(relative) case ['packages', final package, ...final rest]) {
      final uri = await Isolate.resolvePackageUri(
        .parse('package:$package/${rest.join('/')}'),
      );
      if (uri == null) {
        return null;
      }
      file = .fromUri(uri);
    } else {
      file = .new(p.join('web', relative));
    }
    return file.existsSync() ? file : null;
  }

  static const _contentTypes = {
    '.css': 'text/css',
    '.png': 'image/png',
    '.svg': 'image/svg+xml',
    '.woff2': 'font/woff2',
  };

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
      await page.setViewport(.new(width: width, height: height));
      await page.setContent(
        '<!doctype html><style>html,body{margin:0;background:'
        '${transparent ? 'transparent' : Palette.black.hex}}'
        'svg{display:block}</style>'
        '$html',
      );
      return await page.screenshot(
        clip: .new(0, 0, width, height),
        omitBackground: transparent,
      );
    } finally {
      await page.close();
    }
  }
}
