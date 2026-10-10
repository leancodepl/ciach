import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'pill.scopes.dart';

/// A small rounded badge: a version, a licence, a requirement. With [href] it
/// links out; [accent] draws it in the accent color; [icon] leads the text.
@scopedCss
class Pill extends StatelessComponent {
  const Pill(this.text, {this.href, this.accent = false, this.icon, super.key});

  final String text;
  final String? href;
  final bool accent;
  final Icon? icon;

  static const _class = _$PillScope;

  /// Every pill; the social card resizes them.
  static final root = _class.root;
  static final _accent = _class('accent');

  @css
  static List<StyleRule> get styles => [
    css(root.selector).styles(
      display: .inlineFlex,
      padding: .symmetric(vertical: 0.3.rem, horizontal: 0.7.rem),
      border: hairline(border2Color),
      radius: .circular(999.px),
      alignItems: .center,
      gap: .all(0.35.rem),
      color: text2Color,
      fontSize: 0.8.rem,
      fontWeight: .w500,
      backgroundColor: const .rgba(255, 255, 255, 0.02),
    ),
    css(_accent.selector, [
      css('&').styles(
        color: accentColor,
        backgroundColor: accentSoftColor,
        raw: {'border-color': accentAlpha(0.4).value},
      ),
      css('&:hover').styles(raw: {'border-color': 'var(--accent)'}),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final classes = (accent ? root + _accent : root).name;
    final children = [?icon?.build(size: 14), Component.text(text)];
    if (href case final href?) {
      return externalLink(href, classes: classes, children);
    }
    return span(classes: classes, children);
  }
}
