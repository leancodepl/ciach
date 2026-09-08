import 'package:ciach_website/components/button.dart';
import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/pill.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const heroTranscript = r'''
$ ciach
lib/greeting.dart
  15:6  function  danglingFunction  (public)
  24:7  variable  unusedConstant  (public)

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 5 unused declarations in 2 files (scanned 13 files, 44 declarations, 0.5s).''';

class Hero extends StatelessComponent {
  const Hero({required this.version, super.key});

  final String version;

  @css
  static List<StyleRule> get styles => [
    css('.hero').styles(
      position: const .relative(),
      padding: .only(
        top: const .expression('clamp(3.5rem, 9vw, 7rem)'),
        bottom: 3.rem,
      ),
      overflow: .hidden,
      raw: {'isolation': 'isolate'},
    ),
    css('.hero-bg').styles(
      position: const .absolute(),
      zIndex: const ZIndex(-1),
      raw: {
        'inset': '0',
        'background':
            'radial-gradient(55% 45% at 72% 18%, rgba(237, 255, 47, 0.14), '
            'transparent 65%), '
            'radial-gradient(40% 40% at 10% 90%, rgba(237, 255, 47, 0.06), '
            'transparent 60%), '
            'repeating-linear-gradient(-58deg, transparent 0 148px, '
            'rgba(237, 255, 47, 0.09) 148px 149px)',
        'mask-image': 'linear-gradient(to bottom, #000 30%, transparent 100%)',
        '-webkit-mask-image':
            'linear-gradient(to bottom, #000 30%, transparent 100%)',
      },
    ),
    css('.hero-grid')
        .styles(display: .grid, alignItems: .center, gap: .all(3.rem)),
    css('.hero-badges').styles(
      display: .flex,
      margin: .only(bottom: 1.5.rem),
      flexWrap: .wrap,
      gap: .all(0.5.rem),
    ),
    css('.hero h1').styles(
      fontSize: const .expression('clamp(2.5rem, 5.6vw, 4.25rem)'),
      fontWeight: .w700,
      letterSpacing: (-0.035).em,
      lineHeight: const .expression('1.02'),
    ),
    css('.hero-lead').styles(
      maxWidth: 38.rem,
      margin: .only(top: 1.5.rem),
      color: text2Color,
      fontSize: const .expression('clamp(1.1rem, 1.6vw, 1.3rem)'),
    ),
    css('.pronounce').styles(
      maxWidth: 38.rem,
      padding: .only(left: 1.rem),
      margin: .only(top: 1.25.rem),
      border: .only(
        left: BorderSide(color: accentColor, width: 2.px),
      ),
      color: mutedColor,
      fontSize: 0.95.rem,
    ),
    css('.pronounce em').styles(color: textColor, fontStyle: .italic),
    // IPA glyphs: skip the mono stack, which lacks them on Android, and
    // prefer fonts that ship the IPA block before the generic fallback.
    css('.ipa').styles(
      color: text2Color,
      fontFamily: const .list([
        FontFamily('Noto Sans'),
        FontFamily('DejaVu Sans'),
        FontFamily('Segoe UI'),
        FontFamily('Helvetica Neue'),
        FontFamilies.arial,
        FontFamilies.systemUi,
        FontFamilies.sansSerif,
      ]),
      fontSize: 0.95.em,
    ),
    css('.install').styles(margin: .only(top: 2.rem)),
    css('.install-command').styles(
      display: .flex,
      maxWidth: 34.rem,
      padding: .only(
        top: 0.5.rem,
        right: 0.5.rem,
        bottom: 0.5.rem,
        left: 1.rem,
      ),
      border: hairline(border2Color),
      radius: const .circular(radius),
      alignItems: .center,
      gap: .all(0.75.rem),
      backgroundColor: surfaceColor,
      raw: {'box-shadow': shadow},
    ),
    css('.install-command code').styles(
      minWidth: .zero,
      overflow: const .only(x: .auto),
      fontSize: 0.95.rem,
      whiteSpace: .noWrap,
      raw: {'flex': '1'},
    ),
    css('.hero-actions').styles(
      display: .flex,
      margin: .only(top: 1.75.rem),
      flexWrap: .wrap,
      gap: .all(0.75.rem),
    ),
    css('.hero-actions.center').styles(justifyContent: .center),
    css('.hero-demo').styles(minWidth: .zero),
    css.media(MediaQuery.all(minWidth: 1000.px), [
      css('.hero-grid').styles(raw: {'grid-template-columns': '1.05fr 1fr'}),
    ]),
    css.media(MediaQuery.all(maxWidth: 540.px), [
      css('.install-command').styles(flexWrap: .wrap),
      css('.install-command code')
          .styles(order: -1, raw: {'flex-basis': '100%'}),
      css('.install-command .tk-prompt').styles(display: .none),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return section(
      id: 'top',
      classes: 'hero',
      attributes: const {'aria-labelledby': 'hero-heading'},
      [
        const div(classes: 'hero-bg', attributes: {'aria-hidden': 'true'}, []),
        div(classes: 'container hero-grid', [
          div(classes: 'hero-copy', [
            heroBadges(primary: 'v$version'),
            heroHeading(id: 'hero-heading'),
            const p(classes: 'hero-lead', [.text(heroLead)]),
            const p(classes: 'pronounce', [
              em([.text('“Ciach!”')]),
              .text(' '),
              span(
                classes: 'ipa',
                attributes: {'lang': 'pl'},
                [.text('/tɕax/')],
              ),
              .text(' — Polish for the sound of a clean chop.'),
            ]),
            div(classes: 'install', [installCommandBox()]),
            div(classes: 'hero-actions', [
              Button(href: pubUrl, external: true, [
                const .text('Get it on pub.dev'),
                Icon.external.build(size: 18),
              ]),
              Button(href: '/docs', variant: .secondary, [
                Icon.book.build(size: 18),
                const .text('Read the docs'),
              ]),
              Button(href: repoUrl, variant: .secondary, external: true, [
                Icon.github.build(size: 18),
                const .text('GitHub'),
              ]),
            ]),
          ]),
          const div(classes: 'hero-demo', [
            Terminal(
              transcript: heroTranscript,
              title: 'my_app — ciach',
              animated: true,
            ),
          ]),
        ]),
      ],
    );
  }
}

/// The pills above the hero heading. [primary] is the accented one linking to
/// pub.dev: the version on the page, a label on the social card so the card
/// does not change with every release.
Component heroBadges({required String primary}) => p(classes: 'hero-badges', [
  Pill(primary, href: pubUrl, accent: true),
  const Pill('Dart 3.10+'),
  const Pill('Apache-2.0'),
]);

/// The one-line pitch, shared by the page and the social card.
Component heroHeading({String? id}) => h1(id: id, const [
  .text('Dead code detector for '),
  span(classes: 'accent', [.text('Dart')]),
  .text(' and '),
  span(classes: 'accent', [.text('Flutter')]),
  .text('.'),
]);

/// The paragraph under the heading, shared by the page and the social card.
const heroLead =
    'Finds declarations nothing references and removes them for you. One '
    'command, no setup, backed by the Dart analysis server.';

/// The install command in a prompt-style box. The copy button is a client
/// island, so the social card leaves it out.
Component installCommandBox({bool copyButton = true}) =>
    div(classes: 'install-command', [
      const span(
        classes: 'tk-prompt',
        attributes: {'aria-hidden': 'true'},
        [.text(r'$')],
      ),
      const code([.text(installCommand)]),
      if (copyButton) const CopyButton(text: installCommand, label: 'Copy'),
    ]);
