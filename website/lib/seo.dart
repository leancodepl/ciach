/// Everything a crawler or link unfurler reads: metadata, social cards and
/// JSON-LD structured data. Site-wide pieces live in [siteHead]; each page
/// adds its own title, description and canonical URL through [pageHead].
library;

import 'dart:convert';

import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Site-wide `<meta name>` tags rendered by the `Document`.
const siteMeta = {
  'author': 'LeanCode',
  'robots': 'index, follow, max-image-preview:large',
  'theme-color': '#050505',
  'color-scheme': 'dark',
  'application-name': siteName,
  'generator': 'Jaspr',
};

String get _ogImage => '${canonicalUrl}images/og.png';

/// `<head>` children shared by every page: icons, fonts, styles, the social
/// card image and the structured data describing the package itself.
List<Component> siteHead({required String version}) => [
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
  const link(rel: 'preconnect', href: 'https://fonts.googleapis.com'),
  const link(
    rel: 'preconnect',
    href: 'https://fonts.gstatic.com',
    attributes: {'crossorigin': ''},
  ),
  const link(
    rel: 'stylesheet',
    href:
        'https://fonts.googleapis.com/css2'
        '?family=Space+Grotesk:wght@400;500;600;700'
        '&family=JetBrains+Mono:wght@400;600&display=swap',
  ),
  const link(rel: 'stylesheet', href: 'styles.css'),
  ..._properties({
    'og:type': 'website',
    'og:site_name': siteName,
    'og:locale': 'en_US',
    'og:image': _ogImage,
    'og:image:width': '1200',
    'og:image:height': '630',
    'og:image:alt': 'ciach — dead code detector for Dart and Flutter',
  }),
  const meta(name: 'twitter:card', content: 'summary_large_image'),
  meta(name: 'twitter:image', content: _ogImage),
  jsonLd(_softwareSourceCode(version)),
  jsonLd(_webSite()),
];

/// Per-page metadata: title, description, canonical URL and social card text,
/// plus any page-specific [structuredData].
Component pageHead({
  required String title,
  required String description,
  required String path,
  List<Map<String, Object?>> structuredData = const [],
}) {
  final url = '$canonicalUrl$path';
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

Map<String, Object?> _softwareSourceCode(String version) => {
  '@context': 'https://schema.org',
  '@type': ['SoftwareSourceCode', 'SoftwareApplication'],
  'name': siteName,
  'alternateName': 'ciach dead code detector',
  'description': description,
  'url': canonicalUrl,
  'codeRepository': repoUrl,
  'programmingLanguage': 'Dart',
  'runtimePlatform': 'Dart SDK 3.10+',
  'applicationCategory': 'DeveloperApplication',
  'operatingSystem': 'Linux, macOS, Windows',
  'softwareVersion': version,
  'downloadUrl': pubUrl,
  'installUrl': pubUrl,
  'license': 'https://www.apache.org/licenses/LICENSE-2.0',
  'isAccessibleForFree': true,
  'offers': {'@type': 'Offer', 'price': '0', 'priceCurrency': 'USD'},
  'keywords': 'dart, flutter, dead code, unused code, static analysis, cli',
  'author': organization(),
  'maintainer': organization(),
  'image': _ogImage,
};

Map<String, Object?> _webSite() => {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  'name': siteName,
  'url': canonicalUrl,
  'description': description,
  'inLanguage': 'en',
  'publisher': organization(),
};
