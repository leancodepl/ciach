import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class _Feature {
  const _Feature(this.icon, this.title, this.body);

  final Icon icon;
  final String title;
  final String body;
}

const _features = [
  _Feature(
    Icon.layers,
    'Every declaration kind',
    'Classes, enums and their values, functions, methods, constructors, '
        'fields, getters, variables and more.',
  ),
  _Feature(
    Icon.search,
    'Backed by the real analyzer',
    'Reference queries go to the Dart analysis server: the same resolution '
        'your IDE uses, not a regex.',
  ),
  _Feature(
    Icon.git,
    'Built for CI',
    'Annotations inline on the pull request diff and a non-zero exit when '
        'anything turns up.',
  ),
  _Feature(
    Icon.shield,
    'Safe defaults',
    '@override members, operators, entry points, generated files and '
        'toJson() are skipped unless you opt in.',
  ),
  _Feature(
    Icon.braces,
    'Text, JSON or GitHub output',
    'Human-readable by default, machine-readable on request.',
  ),
  _Feature(
    Icon.cog,
    'A config file, optionally',
    'Every flag can live in ciach.yaml. The command line always wins.',
  ),
];

class Features extends StatelessComponent {
  const Features({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'features',
      eyebrow: 'Features',
      heading: 'Sharp, and careful about it.',
      children: [
        ul(classes: 'feature-grid', [
          for (final feature in _features)
            li(classes: 'card feature', [
              span(classes: 'feature-icon', [feature.icon.build(size: 22)]),
              h3([Component.text(feature.title)]),
              p([Component.text(feature.body)]),
            ]),
        ]),
      ],
    );
  }
}
