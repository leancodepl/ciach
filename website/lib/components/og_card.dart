import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The social card behind `og:image`: the landing page's hero laid out for a
/// 1200×630 link preview.
///
/// It is built from the same pieces as [Hero] and styled by the same rules, so
/// it changes with the design. `test/assets_test.dart` renders it to
/// `web/images/og.png` and checks the committed file against it. The card is
/// not part of any page, so it carries its own sizing rules instead of adding
/// them to the site's stylesheet.
class OgCard extends StatelessComponent {
  const OgCard({super.key});

  static const width = 1200;
  static const height = 630;

  /// Font families the card must have loaded before it is rendered.
  static const fonts = ['Space Grotesk', 'JetBrains Mono'];

  /// Sizes the hero pieces for the fixed canvas; colors and fonts come from
  /// the site's own rules. Rendered after them, so equal-specificity rules
  /// such as `.logo-large .logo-mark` lose to the card's.
  static List<StyleRule> get styles => [
    css('.og-card').styles(
      position: const .relative(),
      width: width.px,
      height: height.px,
      padding: .symmetric(vertical: 60.px, horizontal: 80.px),
      boxSizing: .borderBox,
      overflow: .hidden,
      backgroundColor: bgColor,
      raw: {'isolation': 'isolate'},
    ),
    css('.og-card .hero-bg')
        .styles(raw: {'mask-image': 'none', '-webkit-mask-image': 'none'}),
    css('.og-card .logo').styles(fontSize: 2.1.rem),
    css('.og-card .logo-mark')
        .styles(width: 56.px, height: 56.px, radius: .circular(15.px)),
    css('.og-card .logo-mark svg').styles(width: 38.px, height: 38.px),
    css('.og-card .hero-badges').styles(
      margin: .only(top: 34.px, bottom: .zero),
      gap: .all(0.6.rem),
    ),
    css('.og-card .pill').styles(
      padding: .symmetric(vertical: 0.4.rem, horizontal: 0.95.rem),
      fontSize: 1.05.rem,
    ),
    css('.og-card h1').styles(
      margin: .only(top: 18.px),
      color: textColor,
      fontSize: 80.px,
      fontWeight: .w700,
      letterSpacing: (-0.035).em,
      lineHeight: const .expression('1.02'),
    ),
    css('.og-card .hero-lead').styles(
      maxWidth: 60.rem,
      margin: .only(top: 26.px),
      fontSize: 1.9.rem,
      lineHeight: const .expression('1.3'),
    ),
    css('.og-card .og-foot').styles(
      display: .flex,
      position: .absolute(left: 80.px, bottom: 60.px, right: 80.px),
      justifyContent: .spaceBetween,
      alignItems: .center,
    ),
    css('.og-card .install-command').styles(
      padding: .only(
        top: 0.9.rem,
        right: 1.6.rem,
        bottom: 0.9.rem,
        left: 1.4.rem,
      ),
      gap: .all(1.rem),
      raw: {'max-width': 'none'},
    ),
    css('.og-card .install-command code')
        .styles(overflow: .visible, fontSize: 1.55.rem),
    css('.og-card .tk-prompt').styles(fontSize: 1.55.rem),
    css('.og-card .og-by').styles(color: mutedColor, fontSize: 1.35.rem),
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      Style(styles: styles),
      div(classes: 'og-card', [
        const div(classes: 'hero-bg', attributes: {'aria-hidden': 'true'}, []),
        logo(large: true),
        heroBadges(primary: 'pub.dev'),
        heroHeading(),
        const p(classes: 'hero-lead', [.text(heroLead)]),
        div(classes: 'og-foot', [
          installCommandBox(copyButton: false),
          const span(classes: 'og-by', [.text('by LeanCode')]),
        ]),
      ]),
    ]);
  }
}
