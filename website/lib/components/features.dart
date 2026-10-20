import 'package:jaspr/jaspr.dart';
import 'package:leancode_site/leancode_site.dart';

const _features = [
  Feature(
    .layers,
    'Every declaration kind',
    'Classes, enums and their values, functions, methods, constructors, fields, getters, variables and more.',
  ),
  Feature(
    .search,
    'Backed by the real analyzer',
    'Reference queries go to the Dart analysis server: the same resolution your IDE uses, not a regex.',
  ),
  Feature(
    .git,
    'Built for CI',
    'Annotations inline on the pull request diff and a non-zero exit when anything turns up.',
  ),
  Feature(
    .shield,
    'Safe defaults',
    '`@override` members, operators, entry points, generated files and `toJson()` are skipped unless you opt in.',
  ),
  Feature(
    .braces,
    'Text, JSON or GitHub output',
    'Human-readable by default, machine-readable on request.',
  ),
  Feature(
    .cog,
    'A config file, optionally',
    'Every flag can live in `ciach.yaml`. The command line always wins.',
  ),
];

class const Features({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => const Section(
    id: 'features',
    eyebrow: 'Features',
    heading: 'Sharp, and careful about it.',
    children: [FeatureGrid(_features, minWidth: 300)],
  );
}
