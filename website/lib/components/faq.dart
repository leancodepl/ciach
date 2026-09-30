import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'faq.scopes.dart';

class FaqEntry {
  const FaqEntry(this.question, this.answer);

  final String question;
  final String answer;
}

/// Shared with the FAQPage JSON-LD, so the structured data and the visible
/// answers can never drift apart. Backticks mark inline code; the structured
/// data drops them.
const faqEntries = [
  FaqEntry(
    'Does ciach work with Flutter apps?',
    'Yes, with any Dart package. `@override` members such as `build` and '
        '`initState` are skipped by default because frameworks reach them '
        'polymorphically; pass `--overrides` to report them anyway.',
  ),
  FaqEntry(
    'Is it safe to run `ciach --remove`?',
    'It shows the list and asks first, leaves ambiguous multi-declarator '
        'statements alone and marks findings whose removal would not compile '
        'as report-only. Still review the diff, as after any automated '
        'refactor. `--overrides` and `--operators` widen the false-positive '
        'risk.',
  ),
  FaqEntry(
    'My library’s public API is reported as unused.',
    'That is expected from inside the package. Use `--no-public` to report '
        'only private declarations, or keep public findings visible but out '
        'of the exit code with `--set-exit-if-changed` `--no-fail-public`.',
  ),
  FaqEntry(
    'How fast is it?',
    'As fast as the analysis server: the package is analyzed once per run, '
        'then one references query per declaration goes through a pool of 16 '
        'concurrent requests. `--no-public` is by far the cheapest mode.',
  ),
  FaqEntry(
    'Which Dart versions are supported?',
    'Dart 3.10 and newer. ciach analyzes with the SDK it is invoked with, so '
        'scanning newer syntax needs an SDK that can parse it.',
  ),
];

/// FAQ as `<details>` disclosures: no script, every answer in the HTML.
@scopedCss
class Faq extends StatelessComponent {
  const Faq({super.key});

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
          'transition':
              'block-size 0.3s ease, opacity 0.25s ease, '
              'content-visibility 0.3s allow-discrete',
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
        css('& h3').styles(fontSize: 1.1.rem, fontWeight: .w500),
        css('&::after').styles(
          content: '+',
          display: .grid,
          width: 2.rem,
          height: 2.rem,
          border: hairline(border2Color),
          radius: .circular(50.percent),
          transition: .new('transform', duration: 200.ms, curve: .ease),
          flex: .none,
          color: accentColor,
          fontFamily: fontMono,
          raw: {'place-items': 'center'},
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
      for (final (index, entry) in faqEntries.indexed)
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

Map<String, Object?> faqStructuredData() => {
  '@context': 'https://schema.org',
  '@type': 'FAQPage',
  'mainEntity': [
    for (final entry in faqEntries)
      {
        '@type': 'Question',
        'name': _plain(entry.question),
        'acceptedAnswer': {'@type': 'Answer', 'text': _plain(entry.answer)},
      },
  ],
};
