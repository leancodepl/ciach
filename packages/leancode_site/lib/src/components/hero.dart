import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/button.dart';
import 'package:leancode_site/src/components/copy_button.dart';
import 'package:leancode_site/src/components/pill.dart';
import 'package:leancode_site/src/highlight/highlight.dart';
import 'package:leancode_site/src/icons.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:leancode_site/src/styles.dart';

part 'hero.scopes.dart';

/// The landing page's opening: the pills, the [heading], the [lead], the
/// install command and the calls to action on the left, the site's own
/// [aside] such as a terminal or a demo on the right.
@scopedCss
class const Hero({
  /// The children of the `h1`.
  required final List<Component> heading,
  required final String lead,
  required final Component aside,

  /// The pills after the version pill.
  final List<Pill> badges = const [],

  /// Anything between the lead and the install command.
  final List<Component> afterLead = const [],

  /// The buttons under the install command; [siteActions] when null.
  final List<Component>? actions,
  super.key,
}) extends StatelessComponent {
  static const _class = _$HeroScope;

  static final _root = _class.root;
  static final _grid = _class('grid');
  static final _copy = _class('copy');
  static final _install = _class('install');
  static final _demo = _class('demo');

  // Also drawn by the social card, which restyles them for its canvas.

  /// The accent glow and diagonal lines behind the hero.
  static final bg = _class('bg');

  /// The row of pills above the heading.
  static final badgesRow = _class('badges');

  /// The paragraph under the heading.
  static final leadText = _class('lead');

  /// The prompt-style box around the install command.
  static final installCommand = _class('install-command');

  /// A row of call-to-action buttons, also closing the footer.
  static final actionsRow = _class('actions');

  /// Centers [actionsRow].
  static final center = _class('center');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        position: const .relative(),
        padding: .only(
          top: const .expression('clamp(3.5rem, 9vw, 7rem)'),
          bottom: 3.rem,
        ),
        overflow: .hidden,
        raw: {'isolation': 'isolate'},
      ),
      // A display heading: Cabinet Grotesk at 500, tracking 0.
      css('& h1').styles(
        fontSize: const .expression('clamp(2.5rem, 5.6vw, 4.25rem)'),
        fontWeight: .w500,
        lineHeight: const .expression('1.08'),
      ),
    ]),
    css(bg.selector).styles(
      position: const .absolute(
        top: .zero,
        left: .zero,
        bottom: .zero,
        right: .zero,
      ),
      zIndex: const .new(-1),
      raw: {
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
        css('&').styles(gridTemplate: fractionColumns([1.05, 1])),
      ]),
    ]),
    css(_copy.selector, [shrinkableChildren()]),
    css(badgesRow.selector).styles(
      display: .flex,
      margin: .only(bottom: 1.5.rem),
      flexWrap: .wrap,
      gap: .all(0.5.rem),
    ),
    css(leadText.selector).styles(
      maxWidth: 38.rem,
      margin: .only(top: 1.5.rem),
      color: text2Color,
      fontSize: const .expression('clamp(1.1rem, 1.6vw, 1.3rem)'),
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
        shadow: shadow,
        alignItems: .center,
        gap: .all(0.75.rem),
        backgroundColor: surfaceColor,
      ),
      css('& code').styles(
        minWidth: .zero,
        overflow: const .only(x: .auto),
        flex: growToFill,
        fontSize: 0.95.rem,
        whiteSpace: .noWrap,
      ),
      css.media(.all(maxWidth: 540.px), [
        css('&').styles(flexWrap: .wrap),
        css('& code').styles(flex: .basis(100.percent), order: -1),
        css('& ${Highlight.prompt.selector}').styles(display: .none),
      ]),
    ]),
    css(actionsRow.selector, [
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
    final site = Site.of(context);
    return section(
      id: 'top',
      classes: _root.name,
      attributes: const {'aria-labelledby': 'hero-heading'},
      [
        div(
          classes: bg.name,
          attributes: const {'aria-hidden': 'true'},
          const [],
        ),
        div(classes: (Utility.container + _grid).name, [
          div(classes: _copy.name, [
            HeroBadges(primary: 'v${site.version}', others: badges),
            h1(id: 'hero-heading', heading),
            p(classes: leadText.name, [.text(lead)]),
            ...afterLead,
            div(classes: _install.name, const [InstallCommand()]),
            div(classes: actionsRow.name, actions ?? siteActions(site)),
          ]),
          div(classes: _demo.name, [aside]),
        ]),
      ],
    );
  }
}

/// The pills above the hero heading. [primary] is the accented one linking to
/// pub.dev: the version on the page, a label on the social card so the card
/// does not change with every release.
class const HeroBadges({
  required final String primary,
  final List<Pill> others = const [],
  super.key,
}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => p(classes: Hero.badgesRow.name, [
    Pill(primary, href: Site.of(context).pubUrl, accent: true),
    ...others,
  ]);
}

/// The site's install command in a prompt-style box. The copy button is a
/// client island, so the social card leaves it out.
class const InstallCommand({final bool copyButton = true, super.key})
    extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    final command = Site.of(context).installCommand;
    return div(classes: Hero.installCommand.name, [
      span(
        classes: Highlight.prompt.name,
        attributes: const {'aria-hidden': 'true'},
        const [.text(r'$')],
      ),
      code([.text(command)]),
      if (copyButton) CopyButton(text: command, label: 'Copy'),
    ]);
  }
}

/// The calls to action every page shares: pub.dev, the docs and, with
/// [github], the repository.
List<Component> siteActions(SiteConfig site, {bool github = true}) => [
  Button(href: site.pubUrl, external: true, [
    const .text('Get it on pub.dev'),
    Icon.external.build(size: 18),
  ]),
  Button(href: site.docsPath, variant: .secondary, [
    Icon.book.build(size: 18),
    const .text('Read the docs'),
  ]),
  if (github)
    Button(href: site.repoUrl, variant: .secondary, external: true, [
      Icon.github.build(size: 18),
      const .text('GitHub'),
    ]),
];
