import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class FaqEntry {
  const FaqEntry(this.question, this.answer);

  final String question;
  final String answer;
}

/// Shared with the FAQPage JSON-LD in `seo.dart`, so the structured data and
/// the visible answers can never drift apart.
const faqEntries = [
  FaqEntry(
    'What does “ciach” mean?',
    '“Ciach!” (pronounced /t͡ɕax/) is Polish onomatopoeia for a clean chop — '
        'the noise a knife makes right before something falls off. Fitting for '
        'a tool whose job is cutting dead code out of a codebase.',
  ),
  FaqEntry(
    'Does ciach work with Flutter apps?',
    'Yes. ciach analyzes any Dart package, Flutter apps and plugins included, '
        'with the Dart SDK it is invoked with. @override members such as build '
        'and initState are skipped by default because frameworks reach them '
        'polymorphically; pass --overrides to report them anyway.',
  ),
  FaqEntry(
    'How is this different from the analyzer’s unused_element hint?',
    'The analyzer only flags unused private declarations inside a single '
        'library. ciach asks the analysis server for references across the whole '
        'package, so it also finds unused public classes, methods, fields and '
        'enum values, groups them per file, exports JSON or GitHub annotations, '
        'and can remove what it finds.',
  ),
  FaqEntry(
    'Is it safe to run ciach --remove?',
    'It is designed to be, with review. --remove shows every declaration it '
        'is about to delete and asks first, leaves ambiguous multi-declarator '
        'statements alone, and marks findings whose removal would not compile '
        'as report-only. Because it removes whatever the finder reports, '
        'review the diff as you would after any automated refactor, and be '
        'aware that --overrides and --operators widen the false-positive risk.',
  ),
  FaqEntry(
    'My library’s public API is reported as unused. What should I do?',
    'A library package’s public API is legitimately unused from inside the '
        'package. Run ciach --no-public to report only private declarations, '
        'or keep public findings visible but exclude them from the exit code '
        'with --set-exit-if-changed --no-fail-public in CI.',
  ),
  FaqEntry(
    'How fast is it?',
    'Runtime is the analysis server’s: the package is analyzed once per run '
        '(tens of seconds for a large Flutter app), then one references query '
        'per declaration goes through a pool of 16 concurrent requests by '
        'default. --no-public is by far the cheapest mode, and --include or '
        '--exclude narrow the scan while still counting references from '
        'everywhere.',
  ),
  FaqEntry(
    'Which Dart versions are supported?',
    'ciach runs on Dart 3.10 and newer. It analyzes with the SDK it is '
        'invoked with, so scanning code that uses newer language features needs '
        'an SDK new enough to parse them. It understands Dart 3.13 primary '
        'constructors and dot shorthands.',
  ),
  FaqEntry(
    'Can I use it in a monorepo?',
    'Yes. Point ciach at any package root (ciach path/to/package). Config '
        'discovery looks for ciach.yaml only in the analyzed package root, never '
        'in a parent, so each package owns its own settings. In GitHub Actions, '
        'run it from the repository root so annotation paths resolve; the scan '
        'path is prepended automatically.',
  ),
];

class Faq extends StatelessComponent {
  const Faq({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'faq',
      eyebrow: 'FAQ',
      heading: 'Questions, answered.',
      children: [
        div(classes: 'faq-list', [
          for (final (index, entry) in faqEntries.indexed)
            details(
              classes: 'faq-item',
              attributes: {'name': 'faq', if (index == 0) 'open': ''},
              [
                summary([
                  h3([Component.text(entry.question)]),
                ]),
                p([Component.text(entry.answer)]),
              ],
            ),
        ]),
      ],
    );
  }
}
