import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A bordered surface with padding. [classes] adds the caller's own hooks;
/// [listItem] renders an `li` for cards that sit in a list.
class Card extends StatelessComponent {
  const Card(this.children, {this.classes, this.listItem = false, super.key});

  final List<Component> children;
  final String? classes;
  final bool listItem;

  @css
  static List<StyleRule> get styles => [
    css('.card').styles(
      padding: .all(1.5.rem),
      border: hairline(borderColor),
      radius: const .circular(radius),
      transition: .combine([
        Transition('border-color', duration: 200.ms, curve: .ease),
        Transition('transform', duration: 200.ms, curve: .ease),
      ]),
      backgroundColor: surfaceColor,
    ),
    css('.card h3').styles(
      margin: .only(bottom: 0.6.rem),
      fontSize: 1.2.rem,
    ),
    css('.card p').styles(color: text2Color, fontSize: 0.98.rem),
  ];

  @override
  Component build(BuildContext context) {
    final allClasses = classes == null ? 'card' : 'card $classes';
    if (listItem) {
      return li(classes: allClasses, children);
    }
    return div(classes: allClasses, children);
  }
}
