import 'package:ciach_website/components/button.dart';
import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/pill.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'hero.scopes.dart';

const heroTranscript = r'''
$ ciach
lib/greeting.dart
  15:6  function  danglingFunction  (public)
  24:7  variable  unusedConstant  (public)

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 5 unused declarations in 2 files (scanned 13 files, 44 declarations, 0.5s)''';

@scopedCss
class Hero extends StatelessComponent {
  const Hero({required this.version, super.key});

  final String version;

  static const _class = _$HeroScope;

  static final _hero = _class('hero');
  static final _grid = _class('grid');
  static final _copy = _class('copy');
  static final _pronounce = _class('pronounce');
  static final _ipa = _class('ipa');
  static final _install = _class('install');
  static final _demo = _class('demo');

  // Also drawn by the social card, which restyles them for its canvas.

  /// The accent glow and diagonal lines behind the hero.
  static final bg = _class('bg');

  /// The row of pills above the heading.
  static final badges = _class('badges');

  /// The paragraph under the heading.
  static final lead = _class('lead');

  /// The prompt-style box around the install command.
  static final installCommand = _class('install-command');

  /// A row of call-to-action buttons, also closing the footer.
  static final actions = _class('actions');

  /// Centers [actions].
  static final center = _class('center');

  @css
  static List<StyleRule> get styles => [
    css(_hero.selector, [
      css('&').styles(
        position: const .relative(),
        padding: .only(
          top: const .expression('clamp(3.5rem, 9vw, 7rem)'),
          bottom: 3.rem,
        ),
        overflow: .hidden,
        raw: {'isolation': 'isolate'},
      ),
      css('& h1').styles(
        fontSize: const .expression('clamp(2.5rem, 5.6vw, 4.25rem)'),
        fontWeight: .w700,
        letterSpacing: (-0.035).em,
        lineHeight: const .expression('1.02'),
      ),
    ]),
    css(bg.selector).styles(
      position: const .absolute(),
      zIndex: const .new(-1),
      raw: {
        'inset': '0',
        'background':
            'radial-gradient(55% 45% at 72% 18%, ${accentAlpha(0.14).value}, '
            'transparent 65%), '
            'radial-gradient(40% 40% at 10% 90%, ${accentAlpha(0.06).value}, '
            'transparent 60%), '
            'repeating-linear-gradient(-58deg, transparent 0 148px, '
            '${accentAlpha(0.09).value} 148px 149px)',
        'mask-image': 'linear-gradient(to bottom, #000 30%, transparent 100%)',
        '-webkit-mask-image':
            'linear-gradient(to bottom, #000 30%, transparent 100%)',
      },
    ),
    css(_grid.selector, [
      css('&').styles(display: .grid, alignItems: .center, gap: .all(3.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 1000.px), [
        css('&').styles(raw: {'grid-template-columns': '1.05fr 1fr'}),
      ]),
    ]),
    css(_copy.selector, [shrinkableChildren()]),
    css(badges.selector).styles(
      display: .flex,
      margin: .only(bottom: 1.5.rem),
      flexWrap: .wrap,
      gap: .all(0.5.rem),
    ),
    css(lead.selector).styles(
      maxWidth: 38.rem,
      margin: .only(top: 1.5.rem),
      color: text2Color,
      fontSize: const .expression('clamp(1.1rem, 1.6vw, 1.3rem)'),
    ),
    css(_pronounce.selector, [
      css('&').styles(
        maxWidth: 38.rem,
        padding: .only(left: 1.rem),
        margin: .only(top: 1.25.rem),
        border: .only(
          left: .new(color: accentColor, width: 2.px),
        ),
        color: mutedColor,
        fontSize: 0.95.rem,
      ),
      css('& em').styles(color: textColor, fontStyle: .italic),
    ]),
    // IPA glyphs: skip the mono stack, which lacks them on Android, and
    // prefer fonts that ship the IPA block before the generic fallback.
    css(_ipa.selector).styles(
      color: text2Color,
      fontFamily: const .list([
        .new('Noto Sans'),
        .new('DejaVu Sans'),
        .new('Segoe UI'),
        .new('Helvetica Neue'),
        FontFamilies.arial,
        FontFamilies.systemUi,
        FontFamilies.sansSerif,
      ]),
      fontSize: 0.95.em,
    ),
    css(_install.selector).styles(margin: .only(top: 2.rem)),
    css(installCommand.selector, [
      css('&').styles(
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
      css('& code').styles(
        minWidth: .zero,
        overflow: const .only(x: .auto),
        fontSize: 0.95.rem,
        whiteSpace: .noWrap,
        raw: {'flex': '1'},
      ),
      css.media(.all(maxWidth: 540.px), [
        css('&').styles(flexWrap: .wrap),
        css('& code').styles(order: -1, raw: {'flex-basis': '100%'}),
        css('& ${Highlight.prompt.selector}').styles(display: .none),
      ]),
    ]),
    css(actions.selector, [
      css('&').styles(
        display: .flex,
        margin: .only(top: 1.75.rem),
        flexWrap: .wrap,
        gap: .all(0.75.rem),
      ),
      css('&${center.selector}').styles(justifyContent: .center),
    ]),
    css(_demo.selector).styles(minWidth: .zero),
  ];

  @override
  Component build(BuildContext context) {
    return section(
      id: 'top',
      classes: _hero.name,
      attributes: const {'aria-labelledby': 'hero-heading'},
      [
        div(
          classes: bg.name,
          attributes: const {'aria-hidden': 'true'},
          const [],
        ),
        div(classes: (Utility.container + _grid).name, [
          div(classes: _copy.name, [
            heroBadges(primary: 'v$version'),
            heroHeading(id: 'hero-heading'),
            p(classes: lead.name, const [.text(heroLead)]),
            p(classes: _pronounce.name, [
              const em([.text('“Ciach!”')]),
              const .text(' '),
              span(
                classes: _ipa.name,
                attributes: const {'lang': 'pl'},
                const [.text('/tɕax/')],
              ),
              const .text(' — Polish for the sound of a clean chop.'),
            ]),
            div(classes: _install.name, [installCommandBox()]),
            div(classes: actions.name, [
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
          div(classes: _demo.name, const [
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
Component heroBadges({required String primary}) =>
    p(classes: Hero.badges.name, [
      Pill(primary, href: pubUrl, accent: true),
      const Pill('Dart 3.10+'),
      const Pill('Apache-2.0'),
    ]);

/// The one-line pitch, shared by the page and the social card.
Component heroHeading({String? id}) => h1(id: id, [
  const .text('Dead code detector for '),
  span(classes: Utility.accent.name, const [.text('Dart')]),
  const .text(' and '),
  span(classes: Utility.accent.name, const [.text('Flutter')]),
  const .text('.'),
]);

/// The paragraph under the heading, shared by the page and the social card.
const heroLead =
    'Finds declarations nothing references and removes them for you. One '
    'command, no setup, backed by the Dart analysis server.';

/// The install command in a prompt-style box. The copy button is a client
/// island, so the social card leaves it out.
Component installCommandBox({bool copyButton = true}) =>
    div(classes: Hero.installCommand.name, [
      span(
        classes: Highlight.prompt.name,
        attributes: const {'aria-hidden': 'true'},
        const [.text(r'$')],
      ),
      const code([.text(installCommand)]),
      if (copyButton) const CopyButton(text: installCommand, label: 'Copy'),
    ]);
