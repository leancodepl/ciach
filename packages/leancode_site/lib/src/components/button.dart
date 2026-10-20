import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/section.dart';
import 'package:leancode_site/src/palette.dart';
import 'package:leancode_site/src/styles.dart';

part 'button.scopes.dart';

/// How a [Button] is filled.
enum ButtonVariant() {
  /// Accent fill with dark text: the one action a section wants taken.
  primary,

  /// Surface fill with a hairline: the alternative next to a primary button.
  secondary,
}

/// A pill-shaped call to action that links somewhere. [external] links open
/// in a new tab.
@scopedCss
class const Button(
  final List<Component> children, {
  required final String href,
  final ButtonVariant variant = .primary,
  final bool external = false,
  super.key,
}) extends StatelessComponent {
  static const _class = _$ButtonScope;

  static final _root = _class.root;
  static final _primary = _class('primary');
  static final _secondary = _class('secondary');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 0.75.rem, horizontal: 1.2.rem),
        border: hairline(const .new('transparent')),
        cursor: .pointer,
        transition: .combine([
          .new('transform', duration: 150.ms, curve: .ease),
          .new('background-color', duration: 150.ms, curve: .ease),
          .new('border-color', duration: 150.ms, curve: .ease),
          .new('color', duration: 150.ms, curve: .ease),
        ]),
        alignItems: .center,
        gap: .all(0.5.rem),
        fontSize: 0.95.rem,
        fontWeight: .w600,
        lineHeight: const .expression('1'),
        whiteSpace: .noWrap,
      ),
      css('&:hover').styles(transform: .translate(y: (-1).px)),
    ]),
    css(_primary.selector, [
      css('&').styles(color: accentInkColor, backgroundColor: accentColor),
      css('&:hover').styles(
        color: accentInkColor,
        backgroundColor: Palette.ctaYellowLight.color,
      ),
    ]),
    css(_secondary.selector, [
      css('&').styles(
        border: hairline(border2Color),
        color: textColor,
        backgroundColor: surfaceColor,
      ),
      css('&:hover').styles(border: hairline(accentColor), color: textColor),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final variantClass = switch (variant) {
      .primary => _primary,
      .secondary => _secondary,
    };
    final classes = (_root + variantClass).name;
    if (external) {
      return externalLink(href, classes: classes, children);
    }
    return a(href: href, classes: classes, children);
  }
}
