import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/components/shell.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// The site header: the brand on the left, and on the right the three places
/// a visitor can go from any page. Every item is a real link; in-page
/// sections are reached by scrolling.
class NavBar extends StatelessComponent {
  const NavBar({required this.page, super.key});

  final SitePage page;

  @css
  static List<StyleRule> get styles => [
    css('.site-header').styles(
      position: const .sticky(top: .zero),
      zIndex: const ZIndex(50),
      height: headerHeight,
      border: .only(bottom: hairlineSide(borderColor)),
      backdropFilter: .list([const .saturate(1.4), .blur(14.px)]),
      backgroundColor: const Color.rgba(5, 5, 5, 0.75),
      raw: {'-webkit-backdrop-filter': 'saturate(140%) blur(14px)'},
    ),
    css('.nav').styles(
      display: .flex,
      height: 100.percent,
      justifyContent: .spaceBetween,
      alignItems: .center,
      gap: .all(1.rem),
    ),
    css('.brand')
        .styles(display: .inlineFlex, alignItems: .center, color: textColor),
    css('.logo').styles(
      display: .inlineFlex,
      alignItems: .center,
      gap: .all(0.5.rem),
      fontSize: 1.25.rem,
      fontWeight: .w700,
      letterSpacing: (-0.03).em,
    ),
    css('.logo-mark').styles(
      display: .inlineGrid,
      width: 32.px,
      height: 32.px,
      radius: .circular(9.px),
      color: accentInkColor,
      backgroundColor: accentColor,
      raw: {'place-items': 'center'},
    ),
    css('.logo-large').styles(fontSize: 1.6.rem),
    css('.logo-large .logo-mark')
        .styles(width: 44.px, height: 44.px, radius: .circular(12.px)),
    css('.nav-links')
        .styles(display: .flex, alignItems: .center, gap: .all(0.25.rem)),
    css('.nav-links a').styles(
      display: .inlineFlex,
      padding: .symmetric(vertical: 0.5.rem, horizontal: 0.85.rem),
      radius: .circular(999.px),
      alignItems: .center,
      gap: .all(0.45.rem),
      color: text2Color,
      fontSize: 0.95.rem,
      fontWeight: .w500,
    ),
    css('.nav-links a svg').styles(color: mutedColor),
    css('.nav-links a:hover, .nav-links a.is-active')
        .styles(color: textColor, backgroundColor: surfaceColor),
    css('.nav-links a.is-active svg').styles(color: accentColor),
    css.media(MediaQuery.all(maxWidth: 540.px), [
      css('.nav').styles(gap: .all(0.5.rem)),
      css('.nav-links a').styles(
        padding: .symmetric(vertical: 0.5.rem, horizontal: 0.6.rem),
        gap: .all(0.35.rem),
        fontSize: 0.9.rem,
      ),
      css('.nav-links a svg').styles(display: .none),
      css('.nav-links a[aria-label] svg').styles(display: .block),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final onDocs = page == .docs;
    return header(classes: 'site-header', [
      nav(
        classes: 'container nav',
        attributes: const {'aria-label': 'Primary'},
        [
          a(
            href: '/',
            classes: 'brand',
            attributes: const {'aria-label': 'ciach home'},
            [logo()],
          ),
          ul(classes: 'nav-links', [
            li([
              a(
                href: '/docs',
                classes: onDocs ? 'is-active' : null,
                attributes: onDocs ? const {'aria-current': 'page'} : null,
                [Icon.book.build(size: 18), const .text('Docs')],
              ),
            ]),
            li([
              externalLink(pubUrl, [
                Icon.external.build(size: 18),
                const .text('pub.dev'),
              ]),
            ]),
            li([
              externalLink(repoUrl, label: 'ciach on GitHub', [
                Icon.github.build(size: 18),
                const span(classes: 'hide-sm', [.text('GitHub')]),
              ]),
            ]),
          ]),
        ],
      ),
    ]);
  }
}
