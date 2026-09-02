import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A landing-page section with the shared eyebrow / heading / lead header.
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
    super.key,
  });

  final String id;
  final String eyebrow;
  final String heading;
  final String? lead;
  final List<Component> children;
  final String? classes;

  @override
  Component build(BuildContext context) {
    final headingId = '$id-heading';
    return section(
      id: id,
      classes: ['section', ?classes].join(' '),
      attributes: {'aria-labelledby': headingId},
      [
        div(classes: 'container', [
          header(classes: 'section-head', [
            p(classes: 'eyebrow', [Component.text(eyebrow)]),
            h2(id: headingId, [Component.text(heading)]),
            if (lead case final lead?)
              p(classes: 'lead', [Component.text(lead)]),
          ]),
          ...children,
        ]),
      ],
    );
  }
}

/// A docs-page section: a linkable heading followed by its content.
class DocSection extends StatelessComponent {
  const DocSection({
    required this.id,
    required this.heading,
    required this.children,
    super.key,
  });

  final String id;
  final String heading;
  final List<Component> children;

  @override
  Component build(BuildContext context) {
    final headingId = '$id-heading';
    return section(
      id: id,
      classes: 'doc-section',
      attributes: {'aria-labelledby': headingId},
      [
        h2(id: headingId, [Component.text(heading)]),
        ...children,
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
