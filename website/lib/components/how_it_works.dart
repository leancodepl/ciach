import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _verboseTranscript = r'''
$ ciach -v --no-public
[  0.0s] Read config from ciach.yaml.
[  0.0s]   It sets 2 options:
[  0.0s]     public: false
[  0.0s]     exclude: test/**
[  0.0s] Settings for this run:
[  0.0s]   path: /home/me/pkg (command line)
[  0.0s]   public: false (config file)
[  0.0s]   exclude: test/** (config file)
[  0.0s]   concurrency: 16 (default)
[  0.1s] Starting Dart analysis server…
[  0.3s] Collecting declarations from 13 file(s)…
[  0.5s] Scanned 13 file(s) and checked 44 declaration(s) in 478ms: 4 unused, 1 referenced only from doc comments.''';

class _Step {
  const _Step(this.title, this.body);

  final String title;
  final String body;
}

const _steps = [
  _Step(
    'Start the analysis server',
    'ciach launches the Dart analysis server — the one behind your IDE — and '
        'talks to it over the Language Server Protocol. The package is '
        'analyzed once, in full, because incomplete analysis means wrong '
        'reference counts.',
  ),
  _Step(
    'Collect declarations',
    'Scanned files are lexed for every declaration kind, then the skip rules '
        'apply: generated files, @override members, entry points, operators, '
        'toJson(). Files are kept open so the server’s resolved-unit cache '
        'stays warm.',
  ),
  _Step(
    'Ask who references each one',
    'One textDocument/references query per declaration, through a pool of '
        '-j concurrent requests. A zero-reference result gets a '
        'textDocument/definition cross-check, so a resolution the reference '
        'search missed never becomes a false “unused”.',
  ),
  _Step(
    'Report — or chop',
    'Findings are grouped by file with kind, position and visibility. '
        'dartdoc-only mentions are reported separately and never removed. '
        'With --remove, the source is edited in place and you get a diff to '
        'review.',
  ),
];

class HowItWorks extends StatelessComponent {
  const HowItWorks({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'how-it-works',
      eyebrow: 'How it works',
      heading: 'The analyzer does the resolving. ciach does the asking.',
      lead:
          'Dead code detection is only as good as its reference resolution, '
          'so ciach borrows the best one available instead of inventing its '
          'own.',
      children: [
        div(classes: 'how-grid', [
          ol(classes: 'steps', [
            for (final (index, step) in _steps.indexed)
              li(classes: 'step', [
                span(
                  classes: 'step-number',
                  attributes: const {'aria-hidden': 'true'},
                  [Component.text('0${index + 1}')],
                ),
                div([
                  h3([Component.text(step.title)]),
                  p([Component.text(step.body)]),
                ]),
              ]),
          ]),
          const Terminal(transcript: _verboseTranscript, title: 'ciach -v'),
        ]),
      ],
    );
  }
}
