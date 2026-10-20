import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/section.dart';
import 'package:leancode_site/src/styles.dart';

part 'faq.scopes.dart';

/// One question of a [Faq]. Backticks mark inline code in both texts; the
/// structured data drops them.
class const FaqEntry(final String question, final String answer);

/// FAQ as `<details>` disclosures: no script, every answer in the HTML. Pass
/// the same [entries] to [faqStructuredData], so the structured data and the
/// visible answers can never drift apart.
@scopedCss
class const Faq(final List<FaqEntry> entries, {super.key})
    extends StatelessComponent {
  static const _class = _$FaqScope;

  static final _root = _class.root;
  static final _item = _class('item');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector).styles(
      maxWidth: 52.rem,
      border: .only(top: hairlineSide(borderColor)),
    ),
    css(_item.selector, [
      css('&').styles(
        border: .only(bottom: hairlineSide(borderColor)),
        // Lets block-size animate to `auto`, so the answer slides open and
        // shut.
        raw: {'interpolate-size': 'allow-keywords'},
      ),
      // The answer panel: collapsed to zero height and faded out when closed,
      // transitioned to its natural height when open. Browsers without
      // `::details-content` transitions fall back to an instant toggle.
      css('&::details-content').styles(
        opacity: 0,
        overflow: .clip,
        raw: {
          'block-size': '0',
          'transition': 'block-size 0.3s ease, opacity 0.25s ease, content-visibility 0.3s allow-discrete',
        },
      ),
      css('&[open]::details-content')
          .styles(opacity: 1, raw: {'block-size': 'auto'}),
      css('& summary', [
        css('&').styles(
          display: .flex,
          padding: .symmetric(vertical: 1.25.rem, horizontal: .zero),
          cursor: .pointer,
          justifyContent: .spaceBetween,
          alignItems: .center,
          gap: .all(1.rem),
          listStyle: .none,
        ),
        css('&::-webkit-details-marker').styles(display: .none),
        css('& h3').styles(fontSize: 1.1.rem, fontWeight: .w700),
        css('&::after').styles(
          content: '+',
          display: .grid,
          width: 2.rem,
          height: 2.rem,
          border: hairline(border2Color),
          transition: .new('transform', duration: 200.ms, curve: .ease),
          alignItems: .center,
          justifyItems: .center,
          flex: .none,
          color: accentColor,
          fontFamily: fontMono,
        ),
        css('&:hover h3').styles(color: accentColor),
      ]),
      css('&[open] summary::after').styles(transform: .rotate(45.deg)),
      css('& p').styles(
        maxWidth: 46.rem,
        padding: .only(bottom: 1.5.rem),
        color: text2Color,
      ),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return div(classes: _root.name, [
      for (final (index, entry) in entries.indexed)
        details(
          classes: _item.name,
          attributes: {'name': 'faq', if (index == 0) 'open': ''},
          [
            summary([h3(rich(entry.question))]),
            p(rich(entry.answer)),
          ],
        ),
    ]);
  }
}

String _plain(String text) => text.replaceAll('`', '');

/// The `FAQPage` JSON-LD for [entries].
Map<String, Object?> faqStructuredData(List<FaqEntry> entries) => {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': [
    for (final entry in entries)
      {
        '@type': 'Question',
        'name': _plain(entry.question),
        'acceptedAnswer': {'@type': 'Answer', 'text': _plain(entry.answer)},
      },
  ],
};
