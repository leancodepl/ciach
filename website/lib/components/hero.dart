import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const heroTranscript = r'''
$ ciach
lib/greeting.dart
  15:6  function  danglingFunction  (public)
  24:7  variable  unusedConstant  (public)

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 5 unused declarations in 2 files (scanned 13 files, 44 declarations, 0.5s).''';

class const Hero({required final String version, super.key})
    extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return section(
      id: 'top',
      classes: 'hero',
      attributes: const {'aria-labelledby': 'hero-heading'},
      [
        const div(classes: 'hero-bg', attributes: {'aria-hidden': 'true'}, []),
        div(classes: 'container hero-grid', [
          div(classes: 'hero-copy', [
            p(classes: 'hero-badges', [
              externalLink(pubUrl, classes: 'pill pill-accent', [
                .text('v$version'),
              ]),
              const span(classes: 'pill', [.text('Dart 3.10+')]),
              const span(classes: 'pill', [.text('Apache-2.0')]),
            ]),
            const h1(id: 'hero-heading', [
              .text('Dead code detector for '),
              span(classes: 'accent', [.text('Dart')]),
              .text(' and '),
              span(classes: 'accent', [.text('Flutter')]),
              .text('.'),
            ]),
            const p(classes: 'hero-lead', [
              .text(
                'Finds declarations nothing references and removes them for '
                'you. One command, no setup, backed by the Dart analysis server.',
              ),
            ]),
            const p(classes: 'pronounce', [
              em([.text('“Ciach!”')]),
              .text(' '),
              span(
                classes: 'ipa',
                attributes: {'lang': 'pl'},
                [.text('/tɕax/')],
              ),
              .text(' — Polish for the sound of a clean chop.'),
            ]),
            const div(classes: 'install', [
              div(classes: 'install-command', [
                span(
                  classes: 'tk-prompt',
                  attributes: {'aria-hidden': 'true'},
                  [.text(r'$')],
                ),
                code([.text(installCommand)]),
                CopyButton(text: installCommand, label: 'Copy'),
              ]),
            ]),
            div(classes: 'hero-actions', [
              a(href: '/docs', classes: 'button button-primary', [
                const .text('Read the docs'),
                Icon.arrow.build(size: 18),
              ]),
              externalLink(repoUrl, classes: 'button button-secondary', [
                Icon.github.build(size: 18),
                const .text('GitHub'),
              ]),
            ]),
          ]),
          const div(classes: 'hero-demo', [
            Terminal(
              transcript: heroTranscript,
              title: 'my_app — ciach',
              animated: true,
            ),
          ]),
        ]),
      ],
    );
  }
}
