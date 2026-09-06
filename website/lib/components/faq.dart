import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

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
class Faq extends StatelessComponent {
  const Faq({super.key});

  @override
  Component build(BuildContext context) {
    return div(classes: 'faq-list', [
      for (final (index, entry) in faqEntries.indexed)
        details(
          classes: 'faq-item',
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
