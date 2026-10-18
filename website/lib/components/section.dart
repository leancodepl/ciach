import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/site.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'section.scopes.dart';

/// A landing-page section with the shared eyebrow / heading / lead header.
///
/// Every section gets an `id` for in-page anchors and an `aria-labelledby`
/// pointing at its heading, so the outline reads well for crawlers and screen
/// readers alike.
@scopedCss
class const Section({
  required final String id,
  required final String eyebrow,
  required final String heading,
  required final List<Component> children,
  final String? lead,
  final ClassName? classes,
  super.key,
}) extends StatelessComponent {
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
      css('& h2')
          .styles(fontSize: const .expression('clamp(1.9rem, 3.6vw, 2.75rem)')),
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

/// A docs-page section: a linkable heading followed by its content.
@scopedCss
class const DocSection({
  required final String id,
  required final String heading,
  required final List<Component> children,
  super.key,
}) extends StatelessComponent {
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
      css('& h2')
          .styles(fontSize: const .expression('clamp(1.6rem, 2.6vw, 2rem)')),
      css('& h3').styles(fontSize: 1.15.rem),
      css('& p')
          .styles(color: text2Color, lineHeight: const .expression('1.7')),
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
      [DocHeading(fragment: id, id: headingId, text: heading), ...children],
    );
  }
}

/// A docs heading with a button that copies the link to it; [fragment] is
/// the part of that link after `#`. The heading is an `h2`, or an `h3` for a
/// [subsection], with [id] or else [fragment] as its `id`.
@scopedCss
class const DocHeading({
  required final String fragment,
  required final String text,
  final String? id,
  final bool subsection = false,
  super.key,
}) extends StatelessComponent {
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
    final headingId = id ?? fragment;
    final children = [Component.text(text)];
    return div(classes: (_root + (subsection ? _subsection : null)).name, [
      if (subsection)
        h3(id: headingId, children)
      else
        h2(id: headingId, children),
      CopyButton(
        text: '${canonicalUrl}docs#$fragment',
        title: 'Copy link to this section',
        icon: .link,
      ),
    ]);
  }
}

/// Classes for running text, shared by the landing page's sections and the
/// docs.
@scopedCss
abstract final class Prose() {
  static const _class = _$ProseScope;

  /// The small accented label above a heading.
  static final eyebrow = _class('eyebrow');

  /// The paragraph that introduces a section or page.
  static final lead = _class('lead');

  /// The paragraph that links on from a section.
  static final more = _class('more');

  /// A side remark under a table or sample.
  static final note = _class('note');

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
    css('${more.selector} a, ${note.selector} a').styles(
      color: accentColor,
      textDecoration: underlined,
      raw: {'text-underline-offset': '0.15em'},
    ),
    css(note.selector).styles(
      margin: .only(top: 1.rem),
      color: text2Color,
      fontSize: 0.95.rem,
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
