import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
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
    .layers,
    'Every declaration kind',
    'Classes, enums and their values, functions, methods, constructors, '
        'fields, getters, variables and more.',
  ),
  _Feature(
    .search,
    'Backed by the real analyzer',
    'Reference queries go to the Dart analysis server: the same resolution '
        'your IDE uses, not a regex.',
  ),
  _Feature(
    .git,
    'Built for CI',
    'Annotations inline on the pull request diff and a non-zero exit when '
        'anything turns up.',
  ),
  _Feature(
    .shield,
    'Safe defaults',
    '`@override` members, operators, entry points, generated files and '
        '`toJson()` are skipped unless you opt in.',
  ),
  _Feature(
    .braces,
    'Text, JSON or GitHub output',
    'Human-readable by default, machine-readable on request.',
  ),
  _Feature(
    .cog,
    'A config file, optionally',
    'Every flag can live in `ciach.yaml`. The command line always wins.',
  ),
];

class Features extends StatelessComponent {
  const Features({super.key});

  @css
  static List<StyleRule> get styles => [
    css('.feature-grid').styles(
      display: .grid,
      gap: .all(1.rem),
      raw: {
        'grid-template-columns':
            'repeat(auto-fit, minmax(min(100%, 300px), 1fr))',
      },
    ),
    css('.feature')
        .styles(display: .flex, flexDirection: .column, gap: .all(0.6.rem)),
    css('.feature:hover').styles(
      transform: .translate(y: (-2).px),
      raw: {'border-color': 'var(--border-2)'},
    ),
    css('.feature-icon').styles(
      display: .inlineGrid,
      width: 42.px,
      height: 42.px,
      margin: .only(bottom: 0.5.rem),
      border: hairline(accentAlpha(0.3)),
      radius: .circular(12.px),
      color: accentColor,
      backgroundColor: accentSoftColor,
      raw: {'place-items': 'center'},
    ),
    css('.feature h3').styles(margin: .zero),
    css('.feature p').styles(raw: {'flex': '1'}),
  ];

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
              h3([.text(feature.title)]),
              p(rich(feature.body)),
            ]),
        ]),
      ],
    );
  }
}
