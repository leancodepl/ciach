import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A small rounded badge: a version, a licence, a requirement. With [href] it
/// links out; [accent] draws it in the accent color.
class Pill extends StatelessComponent {
  const Pill(this.text, {this.href, this.accent = false, super.key});

  final String text;
  final String? href;
  final bool accent;

  @css
  static List<StyleRule> get styles => [
    css('.pill').styles(
      display: .inlineFlex,
      padding: .symmetric(vertical: 0.3.rem, horizontal: 0.7.rem),
      border: hairline(border2Color),
      radius: .circular(999.px),
      alignItems: .center,
      gap: .all(0.35.rem),
      color: text2Color,
      fontSize: 0.8.rem,
      fontWeight: .w500,
      backgroundColor: const Color.rgba(255, 255, 255, 0.02),
    ),
    css('.pill-accent').styles(
      color: accentColor,
      backgroundColor: accentSoftColor,
      raw: {'border-color': accentAlpha(0.4).value},
    ),
    css('.pill-accent:hover').styles(raw: {'border-color': 'var(--accent)'}),
  ];

  @override
  Component build(BuildContext context) {
    final classes = accent ? 'pill pill-accent' : 'pill';
    if (href case final href?) {
      return externalLink(href, classes: classes, [.text(text)]);
    }
    return span(classes: classes, [.text(text)]);
  }
}
