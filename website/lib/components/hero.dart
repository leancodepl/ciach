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

class Hero extends StatelessComponent {
  const Hero({required this.version, super.key});

  final String version;

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
                Component.text('v$version'),
              ]),
              const span(classes: 'pill', [Component.text('Dart 3.10+')]),
              const span(classes: 'pill', [Component.text('Apache-2.0')]),
            ]),
            const h1(id: 'hero-heading', [
              Component.text('Dead code detector for '),
              span(classes: 'accent', [Component.text('Dart')]),
              Component.text(' and '),
              span(classes: 'accent', [Component.text('Flutter')]),
              Component.text('.'),
            ]),
            const p(classes: 'hero-lead', [
              Component.text(
                'Finds declarations nothing references and removes them for '
                'you. One command, no setup, backed by the Dart analysis server.',
              ),
            ]),
            const p(classes: 'pronounce', [
              em([Component.text('“Ciach!”')]),
              Component.text(' '),
              span(
                classes: 'ipa',
                attributes: {'lang': 'pl'},
                [Component.text('/t͡ɕax/')],
              ),
              Component.text(' — Polish for the sound of a clean chop.'),
            ]),
            const div(classes: 'install', [
              div(classes: 'install-command', [
                span(
                  classes: 'tk-prompt',
                  attributes: {'aria-hidden': 'true'},
                  [Component.text(r'$')],
                ),
                code([Component.text(installCommand)]),
                CopyButton(text: installCommand, label: 'Copy'),
              ]),
            ]),
            div(classes: 'hero-actions', [
              a(href: '/docs', classes: 'button button-primary', [
                const Component.text('Read the docs'),
                Icon.arrow.build(size: 18),
              ]),
              externalLink(repoUrl, classes: 'button button-secondary', [
                Icon.github.build(size: 18),
                const Component.text('GitHub'),
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
