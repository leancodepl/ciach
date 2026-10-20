import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/hero.dart';
import 'package:leancode_site/src/components/pill.dart';
import 'package:leancode_site/src/highlight/highlight.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:leancode_site/src/styles.dart';

part 'og_card.scopes.dart';

/// The social card behind `og:image`: the landing page's hero laid out for a
/// 1200×630 link preview, with the site's large logo, the [badges] after the
/// pub.dev pill, the [heading] and the [lead], which may be shorter than the
/// page's.
///
/// It is built from the same pieces as [Hero] and styled by the same rules, so
/// it changes with the design. A site's asset test renders it to
/// `web/images/og.png` and checks the committed file against it. The card is
/// not part of any page, so it carries its own sizing rules instead of adding
/// them to the site's stylesheet.
@scopedCss
class const OgCard({
  /// The children of the `h1`.
  required final List<Component> heading,
  required final String lead,
  final List<Pill> badges = const [],
  super.key,
}) extends StatelessComponent {
  static const width = 1200;
  static const height = 630;

  static const _class = _$OgCardScope;

  static final _root = _class.root;
  static final _foot = _class('foot');
  static final _by = _class('by');

  /// Sizes the hero pieces for the fixed canvas; colors and fonts come from
  /// the site's own rules. Rendered after them, so equal-specificity rules
  /// lose to the card's.
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        position: const .relative(),
        width: width.px,
        height: height.px,
        padding: .symmetric(vertical: 60.px, horizontal: 80.px),
        boxSizing: .borderBox,
        overflow: .hidden,
        backgroundColor: bgColor,
        raw: {'isolation': 'isolate'},
      ),
      css('& ${Hero.bg.selector}')
          .styles(raw: {'mask-image': 'none', '-webkit-mask-image': 'none'}),
      css('& ${Hero.badgesRow.selector}').styles(
        margin: .only(top: 34.px, bottom: .zero),
        gap: .all(0.6.rem),
      ),
      css('& ${Pill.root.selector}').styles(
        padding: .symmetric(vertical: 0.4.rem, horizontal: 0.95.rem),
        fontSize: 1.05.rem,
      ),
      css('& h1').styles(
        margin: .only(top: 18.px),
        color: textColor,
        fontSize: 80.px,
        fontWeight: .w700,
        letterSpacing: (-0.035).em,
        lineHeight: const .expression('1.02'),
      ),
      css('& ${Hero.leadText.selector}').styles(
        maxWidth: 60.rem,
        margin: .only(top: 26.px),
        fontSize: 1.9.rem,
        lineHeight: const .expression('1.3'),
      ),
      css('& ${_foot.selector}').styles(
        display: .flex,
        position: .absolute(left: 80.px, bottom: 60.px, right: 80.px),
        justifyContent: .spaceBetween,
        alignItems: .center,
      ),
      css('& ${Hero.installCommand.selector}', [
        css('&').styles(
          maxWidth: const .expression('none'),
          padding: .only(
            top: 0.9.rem,
            right: 1.6.rem,
            bottom: 0.9.rem,
            left: 1.4.rem,
          ),
          gap: .all(1.rem),
        ),
        css('& code').styles(overflow: .visible, fontSize: 1.55.rem),
      ]),
      css('& ${Highlight.prompt.selector}').styles(fontSize: 1.55.rem),
      css('& ${_by.selector}').styles(color: mutedColor, fontSize: 1.35.rem),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      Style(styles: styles),
      div(classes: _root.name, [
        div(
          classes: Hero.bg.name,
          attributes: const {'aria-hidden': 'true'},
          const [],
        ),
        Site.of(context).logo(large: true),
        HeroBadges(primary: 'pub.dev', others: badges),
        h1(heading),
        p(classes: Hero.leadText.name, [.text(lead)]),
        div(classes: _foot.name, [
          const InstallCommand(copyButton: false),
          span(classes: _by.name, const [.text('by LeanCode')]),
        ]),
      ]),
    ]);
  }
}
