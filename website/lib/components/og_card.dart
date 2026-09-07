import 'package:ciach_website/components/hero.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The social card behind `og:image`: the landing page's hero laid out for a
/// 1200×630 link preview.
///
/// It is built from the same pieces as [Hero] and styled by the site's
/// stylesheet, so it changes with the design. `test/assets_test.dart` renders
/// it to `web/images/og.png` and checks the committed file against it.
class OgCard extends StatelessComponent {
  const OgCard({super.key});

  static const width = 1200;
  static const height = 630;

  /// Font families the card must have loaded before it is rendered.
  static const fonts = ['Space Grotesk', 'JetBrains Mono'];

  @override
  Component build(BuildContext context) {
    return .fragment([
      const RawText('<style>$_css</style>'),
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

/// Sizes the hero pieces for the fixed 1200×630 canvas; colours and fonts come
/// from `styles.css`.
const _css =
    '''
html, body { margin: 0; background: var(--bg); }
.og-card { position: relative; isolation: isolate; box-sizing: border-box; width: ${OgCard.width}px; height: ${OgCard.height}px; padding: 60px 80px; overflow: hidden; background: var(--bg); }
.og-card .hero-bg { mask-image: none; -webkit-mask-image: none; }
.og-card .logo { font-size: 2.1rem; }
.og-card .logo-mark { width: 56px; height: 56px; border-radius: 15px; }
.og-card .logo-mark svg { width: 30px; height: 30px; }
.og-card .hero-badges { margin: 34px 0 0; gap: 0.6rem; }
.og-card .pill { font-size: 1.05rem; padding: 0.4rem 0.95rem; }
.og-card h1 { margin: 18px 0 0; font-size: 80px; font-weight: 700; line-height: 1.02; letter-spacing: -0.035em; color: var(--text); }
.og-card .hero-lead { max-width: 60rem; margin-top: 26px; font-size: 1.9rem; line-height: 1.3; }
.og-card .og-foot { position: absolute; left: 80px; right: 80px; bottom: 60px; display: flex; align-items: center; justify-content: space-between; }
.og-card .install-command { max-width: none; padding: 0.9rem 1.6rem 0.9rem 1.4rem; gap: 1rem; }
.og-card .install-command code { font-size: 1.55rem; overflow: visible; }
.og-card .tk-prompt { font-size: 1.55rem; }
.og-card .og-by { font-size: 1.35rem; color: var(--muted); }
''';
