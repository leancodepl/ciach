import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/hero.dart';
import 'package:leancode_site/src/components/section.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:leancode_site/src/styles.dart';

part 'footer.scopes.dart';

/// One link of a [FooterColumn]. A link within the site is not [external].
class FooterLink {
  const FooterLink(this.label, this.href, {this.external = true});

  final String label;
  final String href;
  final bool external;
}

/// A titled list of links in the footer.
class FooterColumn {
  const FooterColumn(this.title, this.links);

  FooterColumn._leancode(SiteConfig site)
    : this('LeanCode', [
        FooterLink('leancode.co', site.leancodeUrl),
        FooterLink('Patrol', site.patrolUrl),
        const FooterLink('More packages', SiteConfig.leancodePackagesUrl),
        FooterLink('Hire our team', site.leancodeEstimateUrl),
      ]);

  final String title;
  final List<FooterLink> links;
}

/// The footer: a closing call to action, the brand with its tagline and
/// version, the [columns] of links followed by LeanCode's own, and the
/// license line.
@scopedCss
class SiteFooter extends StatelessComponent {
  const SiteFooter({
    required this.ctaHeading,
    required this.columns,
    this.ctaActions,
    super.key,
  });

  /// The heading of the closing call to action.
  final String ctaHeading;

  /// The buttons under it; [siteActions] without GitHub when null.
  final List<Component>? ctaActions;

  final List<FooterColumn> columns;

  static const _class = _$SiteFooterScope;

  static final _root = _class.root;
  static final _cta = _class('cta');
  static final _ctaInner = _class('cta-inner');
  static final _grid = _class('grid');
  static final _brand = _class('brand');
  static final _bottom = _class('bottom');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      border: .only(top: hairlineSide(borderColor)),
      backgroundColor: bg2Color,
    ),
    css(_cta.selector, [
      css('&').styles(
        padding: const .symmetric(
          vertical: .expression('clamp(4rem, 8vw, 6rem)'),
          horizontal: .zero,
        ),
        border: .only(bottom: hairlineSide(borderColor)),
        backgroundColor: bg2Color,
        raw: {
          'background-image':
              'radial-gradient(50% 60% at 50% 100%, ${accentAlpha(0.12).value}, transparent 70%)',
        },
      ),
      css(
        '& h2',
      ).styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
      css('& p').styles(
        margin: .only(top: 1.rem),
        color: text2Color,
        fontSize: 1.1.rem,
      ),
    ]),
    css(_ctaInner.selector).styles(maxWidth: 40.rem, textAlign: .center),
    css(_grid.selector, [
      css('&').styles(
        display: .grid,
        padding: .symmetric(vertical: 3.5.rem, horizontal: .zero),
        gap: .all(2.5.rem),
      ),
      css('& h3').styles(
        margin: .only(bottom: 0.9.rem),
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.75.rem,
        fontWeight: .w600,
        textTransform: .upperCase,
        letterSpacing: 0.08.em,
      ),
      css('& ul').styles(display: .grid, gap: .all(0.5.rem)),
      css('& li a', [
        css('&').styles(color: text2Color),
        css('&:hover').styles(color: accentColor),
      ]),
      css.media(.all(minWidth: 760.px), [
        css('&').styles(gridTemplate: fractionColumns([1, 1])),
      ]),
      css.media(.all(minWidth: 1000.px), [
        css('&').styles(gridTemplate: fractionColumns([1.6, 1, 1, 1.4])),
      ]),
    ]),
    css('${_brand.selector} p').styles(
      maxWidth: 24.rem,
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 0.95.rem,
    ),
    css(_bottom.selector).styles(
      display: .flex,
      padding: .only(top: 1.5.rem, bottom: 2.rem),
      border: .only(top: hairlineSide(borderColor)),
      flexWrap: .wrap,
      justifyContent: .spaceBetween,
      gap: .all(0.75.rem),
      color: mutedColor,
      fontSize: 0.85.rem,
    ),
    css('${_bottom.selector} a, ${_brand.selector} p a').styles(
      color: text2Color,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
  ];

  @override
  Component build(BuildContext context) {
    final site = Site.of(context);
    return footer(classes: _root.name, [
      section(
        classes: _cta.name,
        attributes: const {'aria-labelledby': 'cta-heading'},
        [
          div(classes: (Utility.container + _ctaInner).name, [
            h2(id: 'cta-heading', [.text(ctaHeading)]),
            div(
              classes: (Hero.actionsRow + Hero.center).name,
              ctaActions ?? siteActions(site, github: false),
            ),
          ]),
        ],
      ),
      div(classes: (Utility.container + _grid).name, [
        div(classes: _brand.name, [
          site.logo(),
          p([
            .text('${site.tagline}. '),
            externalLink(site.changelogUrl, [.text('v${site.version}')]),
            .text(', ${site.licenseName}.'),
          ]),
        ]),
        for (final column in [...columns, FooterColumn._leancode(site)])
          nav(
            attributes: {'aria-label': column.title},
            [
              h3([.text(column.title)]),
              ul([
                for (final link in column.links)
                  li([
                    if (link.external)
                      externalLink(link.href, [.text(link.label)])
                    else
                      a(href: link.href, [.text(link.label)]),
                  ]),
              ]),
            ],
          ),
      ]),
      div(classes: (Utility.container + _bottom).name, [
        p([
          .text('© ${DateTime.now().year} '),
          externalLink(site.leancodeUrl, [const .text('LeanCode')]),
          .text('. ${site.licenseName} license.'),
        ]),
        p([
          const .text('Built with '),
          externalLink('https://jaspr.site', [const .text('Jaspr')]),
          const .text('.'),
        ]),
      ]),
    ]);
  }
}
