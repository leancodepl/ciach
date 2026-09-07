import 'package:ciach_website/styles.dart';
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

  @css
  static List<StyleRule> get styles => [
    css('.section').styles(
      padding: const .symmetric(
        vertical: .expression('clamp(4rem, 8vw, 7rem)'),
        horizontal: .zero,
      ),
      border: .only(top: hairlineSide(borderColor)),
    ),
    css('.section-head').styles(
      maxWidth: 44.rem,
      margin: .only(bottom: 3.rem),
    ),
    css('.section-head.center')
        .styles(textAlign: .center, raw: {'margin-inline': 'auto'}),
    css('.eyebrow').styles(
      display: .inlineFlex,
      margin: .only(bottom: 1.rem),
      alignItems: .center,
      gap: .all(0.5.rem),
      color: accentColor,
      fontFamily: fontMono,
      fontSize: 0.8.rem,
      fontWeight: .w600,
      textTransform: .upperCase,
      letterSpacing: 0.08.em,
    ),
    css('.eyebrow::before').styles(
      content: '',
      width: 1.5.rem,
      height: 2.px,
      backgroundColor: accentColor,
    ),
    css('.section h2')
        .styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
    css('.lead').styles(
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 1.125.rem,
    ),
    css('.section-more').styles(
      margin: .only(top: 1.5.rem),
      fontWeight: .w500,
    ),
    css('.section-more a, .note a').styles(
      color: accentColor,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
    css('.note').styles(
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 0.95.rem,
    ),
    css('.checklist').styles(display: .grid, gap: .all(0.6.rem)),
    css('.checklist li').styles(
      position: const .relative(),
      padding: .only(left: 1.6.rem),
      color: text2Color,
    ),
    css('.checklist li::before').styles(
      content: '',
      position: .absolute(top: 0.7.em, left: .zero),
      width: 0.9.rem,
      height: 2.px,
      backgroundColor: accentColor,
    ),
    css('.doc-section').styles(
      display: .grid,
      padding: .only(top: 3.5.rem),
      margin: .only(top: 3.5.rem),
      border: .only(top: hairlineSide(borderColor)),
      gap: .all(1.75.rem),
    ),
    css('.doc-section h2')
        .styles(fontSize: const .expression('clamp(1.6rem, 2.6vw, 2rem)')),
    css('.doc-section h3').styles(
      margin: .only(top: 1.rem),
      fontSize: 1.15.rem,
    ),
    css('.doc-section p')
        .styles(color: text2Color, lineHeight: const .expression('1.7')),
  ];

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
            p(classes: 'eyebrow', [.text(eyebrow)]),
            h2(id: headingId, [.text(heading)]),
            if (lead case final lead?) p(classes: 'lead', rich(lead)),
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
        h2(id: headingId, [.text(heading)]),
        ...children,
      ],
    );
  }
}

/// Renders [text], turning each backtick-quoted span into an inline code
/// chip, so prose data can mention flags and identifiers without hand-built
/// component lists.
List<Component> rich(String text) => [
  for (final (i, part) in text.split('`').indexed)
    if (part.isNotEmpty)
      if (i.isOdd) code([.text(part)]) else .text(part),
];

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
