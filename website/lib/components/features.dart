import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class _Feature {
  const _Feature(this.icon, this.title, this.body, {this.code});

  final Icon icon;
  final String title;
  final String body;
  final String? code;
}

const _features = [
  _Feature(
    Icon.layers,
    'Every kind of declaration',
    'Classes, mixins, interfaces, enums and their values, extensions, '
        'functions, methods, constructors, fields, getters, setters, variables '
        'and constants. Narrow the hunt with --kinds.',
    code: 'ciach -k class,function,method',
  ),
  _Feature(
    Icon.search,
    'Backed by the real analyzer',
    'ciach drives the Dart analysis server over LSP and asks it who references '
        'each declaration. No regex heuristics: the same resolution your IDE '
        'uses, plus a definition cross-check for what find-references misses.',
  ),
  _Feature(
    Icon.knife,
    'Removes it for you',
    'One flag deletes what was found, doc comments and annotations included, '
        'after a confirmation prompt. Anything whose removal wouldn’t compile '
        'is left for you and clearly marked.',
    code: 'ciach --remove',
  ),
  _Feature(
    Icon.git,
    'Built for CI',
    'GitHub Actions annotations land inline on the PR diff, and '
        '--set-exit-if-changed fails the job when anything turns up. '
        'Gate on private findings only with --no-fail-public.',
    code: 'ciach -f github --set-exit-if-changed',
  ),
  _Feature(
    Icon.braces,
    'Text, JSON or GitHub output',
    'Human-readable by default, machine-readable on request. Pipe the JSON '
        'into jq, a dashboard or your own tooling.',
    code: 'ciach -f json | jq .summary',
  ),
  _Feature(
    Icon.cog,
    'A config file that stays out of the way',
    'Every option can live in ciach.yaml in the package root, keyed by its '
        'long name. The command line always wins, and each package in a '
        'monorepo owns its own config.',
  ),
  _Feature(
    Icon.shield,
    'Safe by default',
    'main, @override members, operators, call, vm:entry-point pragmas, '
        'generated files and toJson() are skipped because each is a known '
        'false-positive source. Opt back in per category.',
  ),
  _Feature(
    Icon.gauge,
    'Fast where it counts',
    'Runtime is the analysis server’s, not the tool’s. --no-public scopes '
        'queries to one library each and surfaces the highest-confidence dead '
        'code; -j tunes how many references queries stay in flight.',
    code: 'ciach --no-public -j 32',
  ),
  _Feature(
    Icon.terminal,
    'Verbose when you need it',
    '-v narrates the run on stderr with timings: the config file read, every '
        'setting and where it came from, each phase, what --remove touched. '
        'stdout stays clean, so -v -f json | jq still works.',
    code: 'ciach -v',
  ),
];

class Features extends StatelessComponent {
  const Features({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'features',
      eyebrow: 'Features',
      heading: 'Everything you need to keep a codebase lean.',
      lead:
          'A static, reference-based dead code finder that understands Dart '
          'the way the analyzer does — and knows when to keep its knife down.',
      children: [
        ul(classes: 'feature-grid', [
          for (final feature in _features)
            li(classes: 'card feature', [
              span(classes: 'feature-icon', [feature.icon.build(size: 22)]),
              h3([Component.text(feature.title)]),
              p([Component.text(feature.body)]),
              if (feature.code case final code?)
                pre(classes: 'feature-code', [
                  Component.element(
                    tag: 'code',
                    children: [
                      const span(classes: 'tk-prompt', [Component.text(r'$ ')]),
                      Component.text(code),
                    ],
                  ),
                ]),
            ]),
        ]),
      ],
    );
  }
}
