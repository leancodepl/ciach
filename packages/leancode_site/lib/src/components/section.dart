import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/copy_button.dart';
import 'package:leancode_site/src/site_config.dart';
import 'package:leancode_site/src/styles.dart';

part 'section.scopes.dart';

/// A landing-page section with the shared eyebrow / heading / lead header.
///
/// Every section gets an `id` for in-page anchors and an `aria-labelledby`
/// pointing at its heading, so the outline reads well for crawlers and screen
/// readers alike.
@scopedCss
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
  final List<Component> children;

  /// May quote identifiers in backticks, which [rich] turns into code chips.
  final String? lead;
  final ClassName? classes;

  static const _class = _$SectionScope;

  static final _root = _class.root;
  static final _head = _class('head');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        padding: const .symmetric(
          vertical: .expression('clamp(4rem, 8vw, 7rem)'),
          horizontal: .zero,
        ),
        border: .only(top: hairlineSide(borderColor)),
      ),
      css(
        '& h2',
      ).styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
    ]),
    css(_head.selector).styles(
      maxWidth: 44.rem,
      margin: .only(bottom: 3.rem),
    ),
  ];

  @override
  Component build(BuildContext context) {
    final headingId = '$id-heading';
    return section(
      id: id,
      classes: (_root + classes).name,
      attributes: {'aria-labelledby': headingId},
      [
        div(classes: Utility.container.name, [
          header(classes: _head.name, [
            p(classes: Prose.eyebrow.name, [.text(eyebrow)]),
            h2(id: headingId, [.text(heading)]),
            if (lead case final lead?) p(classes: Prose.lead.name, rich(lead)),
          ]),
          ...children,
        ]),
      ],
    );
  }
}

/// A docs-page section: a linkable heading followed by its content. The
/// heading's copy button copies a link to it on [pagePath], or on the site's
/// docs path.
@scopedCss
class DocSection extends StatelessComponent {
  const DocSection({
    required this.id,
    required this.heading,
    required this.children,
    this.pagePath,
    super.key,
  });

  final String id;
  final String heading;
  final List<Component> children;
  final String? pagePath;

  static const _class = _$DocSectionScope;

  static final _root = _class.root;

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        display: .grid,
        padding: .only(top: 3.5.rem),
        margin: .only(top: 3.5.rem),
        border: .only(top: hairlineSide(borderColor)),
        gap: .all(1.75.rem),
      ),
      shrinkableChildren(),
      css(
        '& h2',
      ).styles(fontSize: const .expression('clamp(1.6rem, 2.6vw, 2rem)')),
      css('& h3').styles(fontSize: 1.15.rem),
      css(
        '& p',
      ).styles(color: text2Color, lineHeight: const .expression('1.7')),
      css('& p a, & li a').styles(
        color: accentColor,
        textDecoration: underlined,
        raw: {'text-underline-offset': '0.15em'},
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final headingId = '$id-heading';
    return section(
      id: id,
      classes: _root.name,
      attributes: {'aria-labelledby': headingId},
      [
        DocHeading(
          fragment: id,
          id: headingId,
          text: heading,
          pagePath: pagePath,
        ),
        ...children,
      ],
    );
  }
}

/// A docs heading with a button that copies the link to it: [pagePath], or
/// the site's docs path, followed by `#` and [fragment]. The heading is an
/// `h2`, or an `h3` for a [subsection], with [id] or else [fragment] as its
/// `id`.
@scopedCss
class DocHeading extends StatelessComponent {
  const DocHeading({
    required this.fragment,
    required this.text,
    this.id,
    this.pagePath,
    this.subsection = false,
    super.key,
  });

  final String fragment;
  final String text;
  final String? id;
  final String? pagePath;
  final bool subsection;

  static const _class = _$DocHeadingScope;

  static final _root = _class.root;
  static final _subsection = _class('subsection');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(display: .flex, alignItems: .center, gap: .all(0.75.rem)),
      // The button is kept out of the way until the reader points at the
      // heading or tabs to it.
      css('& button').styles(
        opacity: 0.45,
        transition: .new('opacity', duration: 150.ms, curve: .ease),
      ),
      css('&:hover button, & button:focus-visible').styles(opacity: 1),
    ]),
    css(_subsection.selector).styles(margin: .only(top: 1.rem)),
  ];

  @override
  Component build(BuildContext context) {
    final site = Site.of(context);
    final page = pagePath ?? site.docsPath;
    final headingId = id ?? fragment;
    final children = [Component.text(text)];
    return div(classes: (_root + (subsection ? _subsection : null)).name, [
      if (subsection)
        h3(id: headingId, children)
      else
        h2(id: headingId, children),
      CopyButton(
        text: '${site.canonicalUrl}${page.substring(1)}#$fragment',
        title: 'Copy link to this section',
        icon: .link,
      ),
    ]);
  }
}

/// Classes for running text, shared by the landing page's sections and the
/// docs.
@scopedCss
abstract final class Prose {
  static const _class = _$ProseScope;

  /// The small accented label above a heading.
  static final eyebrow = _class('eyebrow');

  /// The paragraph that introduces a section or page.
  static final lead = _class('lead');

  /// The paragraph that links on from a section.
  static final more = _class('more');

  /// A list whose items are marked with a dash in the accent color.
  static final checklist = _class('checklist');

  @css
  static List<StyleRule> get styles => [
    css(eyebrow.selector, [
      css('&').styles(
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
      css('&::before').styles(
        content: '',
        width: 1.5.rem,
        height: 2.px,
        backgroundColor: accentColor,
      ),
    ]),
    css(lead.selector).styles(
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 1.125.rem,
    ),
    css(more.selector).styles(
      margin: .only(top: 1.5.rem),
      fontWeight: .w500,
    ),
    css('${more.selector} a').styles(
      color: accentColor,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
    css(checklist.selector, [
      css('&').styles(display: .grid, gap: .all(0.6.rem)),
      css('& li', [
        css('&').styles(
          position: const .relative(),
          padding: .only(left: 1.6.rem),
          color: text2Color,
        ),
        css('&::before').styles(
          content: '',
          position: .absolute(top: 0.7.em, left: .zero),
          width: 0.9.rem,
          height: 2.px,
          backgroundColor: accentColor,
        ),
      ]),
    ]),
  ];
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
