/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The design system's two typefaces, shipped in this package's `fonts/`
/// directory (see the README there) and served from
/// `packages/leancode_site/fonts/`, so no third-party stylesheet blocks the
/// first paint: Cabinet Grotesk for display and headings, Switzer for body
/// and UI. Code uses the system's monospace stack. `swap` shows the fallback
/// stack until a file arrives.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Where a page finds the font files, relative to its `<base href>`.
const fontsPath = 'packages/leancode_site/fonts';

/// The families, as `document.fonts` names them; the social card must have
/// them loaded before it is rendered.
const fontFamilies = ['Cabinet Grotesk', 'Switzer'];

/// The files that carry everything above the fold: the headings, the body
/// and the UI labels. A page preloads them before the parser reaches the
/// text that needs them.
const preloadedFonts = ['cabinet-grotesk-500', 'switzer-400', 'switzer-600'];

/// One file per weight.
const _faces = {
  'Cabinet Grotesk': {
    500: 'cabinet-grotesk-500',
    600: 'cabinet-grotesk-600',
    700: 'cabinet-grotesk-700',
  },
  'Switzer': {400: 'switzer-400', 600: 'switzer-600'},
};

String _face(String family, int weight, String file) =>
    "@font-face{font-family:'$family';font-style:normal;font-weight:$weight;"
    "font-display:swap;src:url($fontsPath/$file.woff2) format('woff2')}";

/// The `@font-face` rules, inlined into every page's `<head>`.
final fontFaces = [
  for (final MapEntry(key: family, value: weights) in _faces.entries)
    for (final MapEntry(key: weight, value: file) in weights.entries)
      _face(family, weight, file),
].join('\n');

/// The `<head>` children that load the fonts: the preloads and the
/// `@font-face` rules.
List<Component> fontHead() => [
  for (final font in preloadedFonts)
    link(
      rel: 'preload',
      href: '$fontsPath/$font.woff2',
      as: 'font',
      type: 'font/woff2',
      attributes: const {'crossorigin': ''},
    ),
  RawText('<style>$fontFaces</style>'),
];
