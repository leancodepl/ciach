/// The LeanCode palette, named as the design system names it. Every color on
/// the site derives from these swatches: the `:root` tokens in `styles.dart`,
/// the alpha variants for glows and borders, `favicon.svg` and the web
/// manifest. Change a value here and `UPDATE_GOLDENS=1 dart test` regenerates
/// the assets in `web/`.
library;

import 'package:jaspr/dom.dart';

/// A solid color as a packed `0xRRGGBB`, usable as a CSS [color], at an
/// [alpha], or written verbatim into SVG and JSON as [hex].
extension type const Swatch(int _rgb) {
  Color get color => Color.value(_rgb);

  /// `#rrggbb`.
  String get hex => color.value;

  Color alpha(double alpha) =>
      Color.rgba(_rgb >> 16 & 0xff, _rgb >> 8 & 0xff, _rgb & 0xff, alpha);
}

/// Primary surface. LeanCode is black-first; yellow is the exception.
const black = Swatch(0x000000);

/// Text and headings on black.
const white = Swatch(0xffffff);

/// Call to action and emphasis only. Text on it is always [black].
const ctaYellow = Swatch(0xf0ff00);

/// Body copy on dark surfaces.
const bodyGray = Swatch(0xd8d8d4);

/// Secondary text, captions, metadata.
const mutedGray = Swatch(0xa3a3a0);

/// Cards and panels on black, warm-tinted, edged with a [lineColor] hairline.
const surface = Swatch(0x151513);
const surface2 = Swatch(0x1d1d1a);

/// The 1px hairline between surfaces, and a stronger one for controls.
final lineColor = white.alpha(0.12);
final lineStrongColor = white.alpha(0.2);

/// Error and success signals, sparingly.
const error = Swatch(0xe64239);
const success = Swatch(0x80c340);

// The site's own tints, derived from the palette rather than part of it.

/// A section background a step above [black], for the footer.
const nearBlack = Swatch(0x0a0a08);

/// [ctaYellow] lifted for the primary button's hover.
const ctaYellowLight = Swatch(0xf5ff4d);
