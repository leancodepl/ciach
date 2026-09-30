import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/palette.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// How a [Button] is filled.
enum ButtonVariant {
  /// Accent fill with dark text: the one action a section wants taken.
  primary,

  /// Surface fill with a hairline: the alternative next to a primary button.
  secondary,
}

/// A pill-shaped call to action that links somewhere. [external] links open
/// in a new tab.
class Button extends StatelessComponent {
  const Button(
    this.children, {
    required this.href,
    this.variant = .primary,
    this.external = false,
    super.key,
  });

  final List<Component> children;
  final String href;
  final ButtonVariant variant;
  final bool external;

  @css
  static List<StyleRule> get styles => [
    css('.button', [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 0.75.rem, horizontal: 1.2.rem),
        border: hairline(const .new('transparent')),
        radius: .circular(999.px),
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
    css('.button-primary', [
      css('&').styles(color: accentInkColor, backgroundColor: accentColor),
      css('&:hover').styles(
        color: accentInkColor,
        backgroundColor: Palette.ctaYellowLight.color,
      ),
    ]),
    css('.button-secondary', [
      css('&').styles(
        color: textColor,
        backgroundColor: surfaceColor,
        raw: {'border-color': 'var(--border-2)'},
      ),
      css('&:hover')
          .styles(color: textColor, raw: {'border-color': 'var(--accent)'}),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final classes = 'button button-${variant.name}';
    if (external) {
      return externalLink(href, classes: classes, children);
    }
    return a(href: href, classes: classes, children);
  }
}
