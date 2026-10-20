/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The two variable fonts the design uses, shipped in this package's `fonts/`
/// directory (SIL Open Font License, texts alongside the files) and served
/// from `packages/leancode_site/fonts/`, so no third-party stylesheet blocks
/// the first paint. Latin and Latin Extended subsets cover a site's text;
/// `swap` shows the fallback stack until they arrive.
library;

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Where a page finds the font files, relative to its `<base href>`.
const fontsPath = 'packages/leancode_site/fonts';

/// The families, as `document.fonts` names them; the social card must have
/// them loaded before it is rendered.
const fontFamilies = ['Space Grotesk', 'JetBrains Mono'];

/// The Latin subsets carry every glyph above the fold, so a page preloads
/// them before the parser reaches the text that needs them.
const preloadedFonts = ['space-grotesk-latin', 'jetbrains-mono-latin'];

const _latin =
    'U+0000-00FF,U+0131,U+0152-0153,U+02BB-02BC,U+02C6,U+02DA,U+02DC,U+0304,'
    'U+0308,U+0329,U+2000-206F,U+20AC,U+2122,U+2191,U+2193,U+2212,U+2215,'
    'U+FEFF,U+FFFD';
const _latinExt =
    'U+0100-02BA,U+02BD-02C5,U+02C7-02CC,U+02CE-02D7,U+02DD-02FF,U+0304,'
    'U+0308,U+0329,U+1D00-1DBF,U+1E00-1E9F,U+1EF2-1EFF,U+2020,U+20A0-20AB,'
    'U+20AD-20C0,U+2113,U+2C60-2C7F,U+A720-A7FF';

String _face(String family, String file, String weights, String range) =>
    "@font-face{font-family:'$family';font-style:normal;font-weight:$weights;"
    "font-display:swap;src:url($fontsPath/$file.woff2) format('woff2');"
    'unicode-range:$range}';

/// The `@font-face` rules, inlined into every page's `<head>`.
final fontFaces = [
  _face('Space Grotesk', 'space-grotesk-latin', '300 700', _latin),
  _face('Space Grotesk', 'space-grotesk-latin-ext', '300 700', _latinExt),
  _face('JetBrains Mono', 'jetbrains-mono-latin', '100 800', _latin),
  _face('JetBrains Mono', 'jetbrains-mono-latin-ext', '100 800', _latinExt),
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
