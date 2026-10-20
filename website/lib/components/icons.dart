import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/leancode_site.dart';

part 'icons.scopes.dart';

/// The ciach mark: a chop.
const ciachIcon = Icon([
  'M3 21 14.5 9.5',
  'M14.5 9.5 21 3c-1.5 5.5-4 8.5-8 10.5',
  'M9 15 5.5 18.5',
]);

/// The favicon: [ciachIcon] in the CTA yellow on a black square, [size]
/// pixels on a side with corners of [radius] in the 64-unit viewBox. Written
/// to `web/favicon.svg` and rasterized into the other icons by
/// `test/assets_test.dart`.
String ciachFavicon({int size = 64, int radius = 14}) => faviconSvg(
  size: size,
  radius: radius,
  background: Palette.black.hex,
  mark:
      '<g transform="translate(8 8) scale(2)" fill="none" '
      'stroke="${Palette.ctaYellow.hex}" stroke-width="2.4" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '${ciachIcon.paths.map((d) => '<path d="$d"/>').join()}'
      '</g>',
);

/// The ciach word mark: the logo icon next to the package name.
Component logo({bool large = false}) => span(
  classes: (large ? Logo.root + Logo.large : Logo.root).name,
  attributes: const {'aria-hidden': 'true'},
  [
    span(classes: Logo.mark.name, [ciachIcon.build(size: large ? 30 : 20)]),
    span(classes: Logo._text.name, const [.text('ciach')]),
  ],
);

/// The classes of [logo]; [large] is the social card's size.
@scopedCss
abstract final class Logo() {
  static const _class = _$LogoScope;

  static final root = _class.root;
  static final mark = _class('mark');
  static final large = _class('large');
  static final _text = _class('text');

  @css
  static List<StyleRule> get styles => [
    css(root.selector).styles(
      display: .inlineFlex,
      alignItems: .center,
      gap: .all(0.5.rem),
      fontFamily: fontDisplay,
      fontSize: 1.25.rem,
      fontWeight: .w700,
    ),
    css(mark.selector).styles(
      display: .inlineGrid,
      width: 32.px,
      height: 32.px,
      alignItems: .center,
      justifyItems: .center,
      color: accentInkColor,
      backgroundColor: accentColor,
    ),
    css(large.selector, [
      css('&').styles(fontSize: 2.1.rem),
      css('& ${mark.selector}').styles(width: 56.px, height: 56.px),
    ]),
  ];
}
