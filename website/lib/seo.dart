/// Everything a crawler or link unfurler reads: metadata, social cards and
/// JSON-LD structured data.
library;

import 'dart:convert';

import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const pageTitle = '$siteName — $tagline';

/// `<meta name>` tags rendered by the `Document`.
const seoMeta = {
  'description': description,
  'keywords':
      'dart dead code, flutter dead code, unused code detector, dart unused '
      'classes, remove unused code dart, dart static analysis, flutter linter, '
      'ciach, leancode',
  'author': 'LeanCode',
  'robots': 'index, follow, max-image-preview:large',
  'theme-color': '#050505',
  'color-scheme': 'dark',
  'application-name': siteName,
  'generator': 'Jaspr',
};

/// Extra `<head>` children: canonical, icons, social cards and structured data.
List<Component> seoHead({required String version}) {
  final ogImage = '${canonicalUrl}images/og.png';
  return [
    link(rel: 'canonical', href: canonicalUrl),
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
    ..._property({
      'og:type': 'website',
      'og:site_name': siteName,
      'og:locale': 'en_US',
      'og:url': canonicalUrl,
      'og:title': pageTitle,
      'og:description': description,
      'og:image': ogImage,
      'og:image:width': '1200',
      'og:image:height': '630',
      'og:image:alt': 'ciach — dead code detector for Dart and Flutter',
    }),
    const meta(name: 'twitter:card', content: 'summary_large_image'),
    const meta(name: 'twitter:title', content: pageTitle),
    const meta(name: 'twitter:description', content: description),
    meta(name: 'twitter:image', content: ogImage),
    _jsonLd(_softwareSourceCode(version)),
    _jsonLd(_webSite()),
    _jsonLd(_faqPage()),
  ];
}

List<Component> _property(Map<String, String> properties) => [
  for (final MapEntry(key: property, value: content) in properties.entries)
    meta(attributes: {'property': property, 'content': content}),
];

Component _jsonLd(Map<String, Object?> data) => script(
  attributes: const {'type': 'application/ld+json'},
  // Escape "</" so the JSON can never terminate the script element early.
  content: jsonEncode(data).replaceAll('</', r'<\/'),
);

Map<String, Object?> _organization() => {
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
  'author': _organization(),
  'maintainer': _organization(),
  'image': '${canonicalUrl}images/og.png',
};

Map<String, Object?> _webSite() => {
  '@context': 'https://schema.org',
  '@type': 'WebSite',
  'name': siteName,
  'url': canonicalUrl,
  'description': description,
  'inLanguage': 'en',
  'publisher': _organization(),
};

Map<String, Object?> _faqPage() => {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': [
    for (final entry in faqEntries)
      {
        '@type': 'Question',
        'name': entry.question,
        'acceptedAnswer': {'@type': 'Answer', 'text': entry.answer},
      },
  ],
};
