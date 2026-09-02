import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _workflow = '''
name: dead-code

on: [pull_request]

jobs:
  ciach:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - uses: dart-lang/setup-dart@v1
      - run: dart pub get
      # Annotate the PR diff and fail the job when anything is found.
      - run: dart run ciach -f github --set-exit-if-changed''';

const _config = '''
# ciach.yaml — every option, keyed by its long name minus the "--".
public: false                     # --no-public
exclude: ['test/**', 'tool/**']   # repeatable options take a list
kinds: [class, function, method]
format: github
set-exit-if-changed: true''';

const _install = r'''
$ dart pub global activate ciach
$ ciach                                  # current package
$ ciach path/to/package                  # another package
$ ciach --no-public -f json              # private-only, as JSON
$ ciach -f github --set-exit-if-changed  # CI: annotations, non-zero on finds
$ ciach --remove                         # delete findings, asks first
$ ciach --remove --force                 # …without asking''';

class CiSection extends StatelessComponent {
  const CiSection({super.key});

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'ci',
      eyebrow: 'Get started',
      heading: 'From first run to a gate on every pull request.',
      lead:
          'Install it once and run it anywhere, or pin it as a dev dependency '
          'so the whole team and CI use the same version.',
      children: [
        div(id: 'get-started', classes: 'ci-grid', [
          div(classes: 'ci-col', [
            h3([Component.text('1. Install and run')]),
            p([
              Component.text(
                'A global install puts a ciach command in ~/.pub-cache/bin, '
                'compiled ahead of time so there is no JIT warm-up per run. '
                'As a dev dependency, prefix commands with dart run.',
              ),
            ]),
            Terminal(
              transcript: _install,
              title: 'usage',
              copyText: 'dart pub global activate ciach',
            ),
          ]),
          div(classes: 'ci-col', [
            h3([Component.text('2. Gate pull requests')]),
            p([
              Component.text(
                'Each finding becomes an annotation inline on the diff. For a '
                'library whose public API is legitimately unused from the '
                'inside, add --no-fail-public to still surface those findings '
                'while failing only on unused private declarations.',
              ),
            ]),
            CodeBlock(
              code: _workflow,
              language: Language.yaml,
              title: '.github/workflows/dead-code.yml',
            ),
          ]),
          div(classes: 'ci-col', [
            h3([Component.text('3. Make it stick')]),
            p([
              Component.text(
                'Commit a ciach.yaml next to pubspec.yaml so nobody has to '
                'remember the flags. Command line beats config file beats '
                'default, even when the flag matches the default, and a '
                'repeatable option on the command line replaces the list '
                'rather than appending to it.',
              ),
            ]),
            CodeBlock(
              code: _config,
              language: Language.yaml,
              title: 'ciach.yaml',
            ),
          ]),
        ]),
      ],
    );
  }
}
