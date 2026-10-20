/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// Everything a crawler or link unfurler reads: metadata, social cards and
/// JSON-LD structured data. Site-wide pieces live in [SiteHead]; each page
/// adds its own title, description and canonical URL through [PageHead].
library;

import 'dart:convert';

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:leancode_site/src/fonts.dart';
import 'package:leancode_site/src/palette.dart';
import 'package:leancode_site/src/site_config.dart';

/// Site-wide `<meta name>` tags for the `Document`.
Map<String, String> siteMeta(SiteConfig site) => {
  'author': 'LeanCode',
  'robots': 'index, follow, max-image-preview:large',
  'theme-color': Palette.black.hex,
  'color-scheme': 'dark',
  'application-name': site.name,
  'generator': 'Jaspr',
};

/// `web/site.webmanifest`, which a site's asset test writes so that its colors
/// follow the palette. [shortDescription] is the one line a home screen shows.
String webManifest(SiteConfig site, {required String shortDescription}) =>
    '${const JsonEncoder.withIndent('  ').convert({
      'name': site.title,
      'short_name': site.name,
      'description': shortDescription,
      'start_url': './',
      'display': 'browser',
      'background_color': Palette.black.hex,
      'theme_color': Palette.black.hex,
      'icons': [
        {'src': 'favicon.svg', 'sizes': 'any', 'type': 'image/svg+xml'},
        {'src': 'icon-192.png', 'sizes': '192x192', 'type': 'image/png', 'purpose': 'any maskable'},
        {'src': 'icon-512.png', 'sizes': '512x512', 'type': 'image/png', 'purpose': 'any maskable'},
      ],
    })}\n';

String _ogImage(SiteConfig site) => '${site.canonicalUrl}images/og.png';

/// `<head>` children shared by every page: icons, fonts, the social card
/// image and the structured data describing the package itself.
class SiteHead extends StatelessComponent {
  const SiteHead({super.key});

  @override
  Component build(BuildContext context) {
    final site = Site.of(context);
    final ogImage = _ogImage(site);
    return .fragment([
      const link(
        rel: 'icon',
        href: 'favicon.ico',
        attributes: {'sizes': '32x32'},
      ),
      const link(rel: 'icon', href: 'favicon.svg', type: 'image/svg+xml'),
      const link(
        rel: 'icon',
        href: 'favicon.png',
        type: 'image/png',
        attributes: {'sizes': '96x96'},
      ),
      const link(rel: 'apple-touch-icon', href: 'apple-touch-icon.png'),
      const link(rel: 'manifest', href: 'site.webmanifest'),
      const link(rel: 'sitemap', href: 'sitemap.xml', type: 'application/xml'),
      ...fontHead(),
      ..._properties({
        'og:type': 'website',
        'og:site_name': site.name,
        'og:locale': 'en_US',
        'og:image': ogImage,
        'og:image:width': '1200',
        'og:image:height': '630',
        'og:image:alt': site.title,
      }),
      const meta(name: 'twitter:card', content: 'summary_large_image'),
      meta(name: 'twitter:image', content: ogImage),
      jsonLd(_softwareSourceCode(site)),
      jsonLd(_webSite(site)),
    ]);
  }
}

/// Per-page metadata: title, description, canonical URL and social card text,
/// plus any page-specific [structuredData]. [path] is relative to the site
/// root: `''` for the landing page, `docs` for the docs.
class PageHead extends StatelessComponent {
  const PageHead({
    required this.title,
    required this.description,
    required this.path,
    this.structuredData = const [],
    super.key,
  });

  final String title;
  final String description;
  final String path;
  final List<Map<String, Object?>> structuredData;

  @override
  Component build(BuildContext context) {
    final url = '${Site.of(context).canonicalUrl}$path';
    return Document.head(
      title: title,
      meta: {
        'description': description,
        'twitter:title': title,
        'twitter:description': description,
      },
      children: [
        link(rel: 'canonical', href: url),
        ..._properties({
          'og:url': url,
          'og:title': title,
          'og:description': description,
        }),
        for (final data in structuredData) jsonLd(data),
      ],
    );
  }
}

List<Component> _properties(Map<String, String> properties) => [
  for (final MapEntry(key: property, value: content) in properties.entries)
    meta(attributes: {'property': property, 'content': content}),
];

/// A `<script type="application/ld+json">` block.
Component jsonLd(Map<String, Object?> data) => script(
  attributes: const {'type': 'application/ld+json'},
  // Escape "</" so the JSON can never terminate the script element early.
  content: jsonEncode(data).replaceAll('</', r'<\/'),
);

/// LeanCode as the author and publisher in the structured data.
Map<String, Object?> organization() => {
  '@type': 'Organization',
  'name': 'LeanCode',
  'url': 'https://leancode.co/',
  'logo': 'https://leancodepublic.blob.core.windows.net/public/wide.png',
  'sameAs': [
    'https://github.com/leancodepl',
    'https://pub.dev/publishers/leancode.co',
  ],
};

Map<String, Object?> _softwareSourceCode(SiteConfig site) => {
  '@context': 'https://schema.org',
  '@type': ['SoftwareSourceCode', 'SoftwareApplication'],
  'name': site.name,
  'alternateName': ?site.alternateName,
  'description': site.description,
  'url': site.canonicalUrl,
  'codeRepository': site.repoUrl,
  'programmingLanguage': 'Dart',
  'runtimePlatform': site.runtimePlatform,
  'applicationCategory': 'DeveloperApplication',
  'operatingSystem': 'Linux, macOS, Windows',
  'softwareVersion': site.version,
  'downloadUrl': site.pubUrl,
  'installUrl': site.pubUrl,
  'license': site.licenseUrl,
  'isAccessibleForFree': true,
  'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
  'keywords': site.keywords.join(', '),
  'author': organization(),
  'maintainer': organization(),
  'image': _ogImage(site),
};

Map<String, Object?> _webSite(SiteConfig site) => {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  'name': site.name,
  'url': site.canonicalUrl,
  'description': site.description,
  'inLanguage': 'en',
  'publisher': organization(),
};
