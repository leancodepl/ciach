/// Design tokens and the site-wide rules: the reset, typography and shared
/// utilities. Everything else lives next to the component it styles, in `@css`
/// getters; Jaspr collects all of them into one stylesheet, global rules
/// first, and inlines it into every page.
library;

import 'package:jaspr/dom.dart';

// ---------- Tokens ----------
//
// The palette and metrics are CSS custom properties on `:root`, so the values
// below are the variables, and the definitions sit in [styles].

const bgColor = Color.variable('--bg');
const bg2Color = Color.variable('--bg-2');
const surfaceColor = Color.variable('--surface');
const surface2Color = Color.variable('--surface-2');
const borderColor = Color.variable('--border');
const border2Color = Color.variable('--border-2');
const textColor = Color.variable('--text');
const text2Color = Color.variable('--text-2');
const mutedColor = Color.variable('--muted');
const accentColor = Color.variable('--accent');
const accentInkColor = Color.variable('--accent-ink');
const accentSoftColor = Color.variable('--accent-soft');
const dangerColor = Color.variable('--danger');
const okColor = Color.variable('--ok');

const fontSans = FontFamily.variable('--font-sans');
const fontMono = FontFamily.variable('--font-mono');

const radius = Unit.variable('--radius');
const radiusSm = Unit.variable('--radius-sm');
const headerHeight = Unit.variable('--header-h');

/// `var(--shadow)`, for the `box-shadow` slot of a `raw` map: `BoxShadow` has no
/// variable form.
const shadow = 'var(--shadow)';

/// The accent at a given alpha, for borders and glows.
Color accentAlpha(double alpha) => Color.rgba(237, 255, 47, alpha);

/// A 1px solid border in [color].
Border hairline(Color color) => Border.all(color: color, width: 1.px);

/// One side of a [hairline], for `Border.only`.
BorderSide hairlineSide(Color color) => BorderSide(color: color, width: 1.px);

/// Everything the page needs before any component draws: tokens, the reset,
/// typography and utilities.
@css
List<StyleRule> get styles => [
  ..._tokens,
  ..._reset,
  ..._utilities,
  ..._motion,
];

List<StyleRule> get _tokens => [
  css(':root').styles(
    raw: {
      '--bg': '#050505',
      '--bg-2': '#0b0b0d',
      '--surface': '#101013',
      '--surface-2': '#16161b',
      '--border': '#23232b',
      '--border-2': '#33333e',
      '--text': '#f4f4f1',
      '--text-2': '#b7b7b3',
      '--muted': '#7d7d84',
      '--accent': '#edff2f',
      '--accent-2': '#c9dc00',
      '--accent-ink': '#0b0c00',
      '--accent-soft': 'rgba(237, 255, 47, 0.12)',
      '--danger': '#ff5d5d',
      '--ok': '#58e08a',
      '--tk-keyword': '#c792ea',
      '--tk-type': '#82aaff',
      '--tk-string': '#c3e88d',
      '--tk-number': '#f78c6c',
      '--tk-comment': '#676e95',
      '--tk-annotation': '#ffcb6b',
      '--tk-function': '#89ddff',
      '--font-sans':
          "'Space Grotesk', ui-sans-serif, system-ui, -apple-system, "
          "'Segoe UI', Roboto, sans-serif",
      '--font-mono':
          "'JetBrains Mono', ui-monospace, SFMono-Regular, Menlo, Consolas, "
          'monospace',
      '--radius': '14px',
      '--radius-sm': '8px',
      '--container': '1160px',
      '--header-h': '68px',
      '--shadow': '0 24px 60px -32px rgba(0, 0, 0, 0.9)',
      'color-scheme': 'dark',
    },
  ),
];

List<StyleRule> get _reset => [
  css('*, *::before, *::after').styles(boxSizing: .borderBox),
  css('html').styles(
    raw: {
      'scroll-behavior': 'smooth',
      'scroll-padding-top': 'calc(var(--header-h) + 16px)',
      '-webkit-text-size-adjust': '100%',
    },
  ),
  css('body').styles(
    margin: .zero,
    color: textColor,
    fontFamily: fontSans,
    fontSize: 1.0625.rem,
    lineHeight: const .expression('1.6'),
    backgroundColor: bgColor,
    raw: {
      '-webkit-font-smoothing': 'antialiased',
      'text-rendering': 'optimizeLegibility',
    },
  ),
  css('h1, h2, h3').styles(
    margin: .zero,
    fontWeight: .w600,
    letterSpacing: (-0.02).em,
    lineHeight: const .expression('1.15'),
    raw: {'text-wrap': 'balance'},
  ),
  css('p').styles(margin: .zero),
  css('a').styles(color: .inherit, textDecoration: .none),
  css('a:hover').styles(color: accentColor),
  css(':focus-visible').styles(
    radius: .circular(4.px),
    outline: Outline(
      color: accentColor,
      style: .solid,
      width: OutlineWidth(2.px),
      offset: 3.px,
    ),
  ),
  css('code, pre, kbd')
      .styles(fontFamily: fontMono, raw: {'font-feature-settings': "'liga' 0"}),
  // Inline code chips. A flag or identifier never breaks at one of its
  // hyphens.
  css('p code, li code, td code, th code').styles(
    padding: .symmetric(vertical: 0.1.em, horizontal: 0.4.em),
    border: hairline(borderColor),
    radius: .circular(6.px),
    fontSize: 0.85.em,
    whiteSpace: .noWrap,
    backgroundColor: surfaceColor,
  ),
  css('ul, ol').styles(padding: .zero, margin: .zero, listStyle: .none),
  css('svg').styles(
    display: .inlineBlock,
    flex: .none,
    raw: {'vertical-align': 'middle'},
  ),
];

List<StyleRule> get _utilities => [
  css('.container').styles(
    width: const .expression('min(100% - 2.5rem, var(--container))'),
    raw: {'margin-inline': 'auto'},
  ),
  // Grid and flex children may hold wide code samples; let them shrink and
  // scroll instead of stretching the page.
  css(
    '.hero-grid > *, .hero-copy > *, .ciach-grid > *, .feature-grid > *, '
    '.docs > *, .doc-section > *, .tab-panel, .card',
  ).styles(minWidth: .zero),
  css('.sr-only').styles(
    width: 1.px,
    height: 1.px,
    padding: .zero,
    margin: .all((-1).px),
    overflow: .hidden,
    whiteSpace: .noWrap,
    raw: {
      'position': 'absolute !important',
      'clip': 'rect(0 0 0 0)',
      'border': '0',
    },
  ),
  css('.skip-link').styles(
    position: .fixed(top: 12.px, left: 12.px),
    zIndex: const ZIndex(100),
    padding: .symmetric(vertical: 0.6.rem, horizontal: 1.rem),
    radius: const .circular(radiusSm),
    transition: Transition('transform', duration: 200.ms, curve: .ease),
    transform: .translate(y: (-200).percent),
    color: accentInkColor,
    fontWeight: .w600,
    backgroundColor: accentColor,
  ),
  css('.skip-link:focus').styles(transform: const .translate(y: .zero)),
  css('.accent').styles(color: accentColor),
  css('.muted').styles(color: mutedColor),
  css('.hide-sm').styles(display: .inline),
  css.media(MediaQuery.all(maxWidth: 540.px), [
    css('.hide-sm').styles(display: .none),
  ]),
];

// Motion is a garnish here; readers who asked for less of it get none.
List<StyleRule> get _motion => [
  css.media(const MediaQuery.raw('(prefers-reduced-motion: reduce)'), [
    css('html').styles(raw: {'scroll-behavior': 'auto'}),
    css('*, *::before, *::after').styles(
      raw: {
        'animation-duration': '0.01ms !important',
        'animation-iteration-count': '1 !important',
        'transition-duration': '0.01ms !important',
      },
    ),
  ]),
];
