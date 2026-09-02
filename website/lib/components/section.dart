import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A landmark section with the shared eyebrow / heading / lead header.
///
/// Every section gets an `id` for in-page anchors and an `aria-labelledby`
/// pointing at its heading, so the outline reads well for crawlers and screen
/// readers alike.
class Section extends StatelessComponent {
  const Section({
    required this.id,
    required this.eyebrow,
    required this.heading,
    required this.children,
    this.lead,
    this.classes,
    this.alignCenter = false,
    super.key,
  });

  final String id;
  final String eyebrow;
  final String heading;
  final String? lead;
  final List<Component> children;
  final String? classes;
  final bool alignCenter;

  @override
  Component build(BuildContext context) {
    final headingId = '$id-heading';
    return section(
      id: id,
      classes: ['section', ?classes].join(' '),
      attributes: {'aria-labelledby': headingId},
      [
        div(classes: 'container', [
          header(
            classes: alignCenter ? 'section-head center' : 'section-head',
            [
              p(classes: 'eyebrow', [Component.text(eyebrow)]),
              h2(id: headingId, [Component.text(heading)]),
              if (lead case final lead?)
                p(classes: 'lead', [Component.text(lead)]),
            ],
          ),
          ...children,
        ]),
      ],
    );
  }
}

/// An external link that opens in a new tab with the right `rel`.
Component externalLink(
  String href,
  List<Component> children, {
  String? classes,
  String? label,
}) => a(
  href: href,
  classes: classes,
  attributes: {'target': '_blank', 'rel': 'noopener', 'aria-label': ?label},
  children,
);
