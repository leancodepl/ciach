import 'package:leancode_site/leancode_site.dart';

/// The questions on the docs page, shown by `Faq` and repeated in the
/// FAQPage JSON-LD.
const faqEntries = [
  FaqEntry(
    'Does ciach work with Flutter apps?',
    'Yes, with any Dart package. `@override` members such as `build` and '
        '`initState` are skipped by default because frameworks reach them '
        'polymorphically; pass `--also overrides` to report them anyway.',
  ),
  FaqEntry(
    'Is it safe to run `ciach --remove`?',
    'It shows the list and asks first, leaves ambiguous multi-declarator '
        'statements alone and marks findings whose removal would not compile '
        'as report-only. Still review the diff, as after any automated '
        'refactor. `--also overrides,operators` widens the false-positive '
        'risk.',
  ),
  FaqEntry(
    'My library’s public API is reported as unused.',
    'ciach can’t see importers outside the analysis. List the package in '
        '`exported-packages` in `ciach.yaml`, and what other packages can '
        'import from it is left out.',
  ),
  FaqEntry(
    'How fast is it?',
    'A large Flutter app takes tens of seconds. `--no-public` is by far the cheapest mode.',
  ),
  FaqEntry(
    'Which Dart versions are supported?',
    'Dart 3.10 and newer. ciach analyzes with the SDK it is invoked with, so '
        'scanning newer syntax needs an SDK that can parse it.',
  ),
];
