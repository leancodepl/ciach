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
            heroBadges(primary: 'v$version'),
            heroHeading(id: 'hero-heading'),
            const p(classes: 'hero-lead', [.text(heroLead)]),
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
            div(classes: 'install', [installCommandBox()]),
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

/// The pills above the hero heading. [primary] is the accented one linking to
/// pub.dev: the version on the page, a label on the social card so the card
/// does not change with every release.
Component heroBadges({required String primary}) => p(classes: 'hero-badges', [
  externalLink(pubUrl, classes: 'pill pill-accent', [.text(primary)]),
  const span(classes: 'pill', [.text('Dart 3.10+')]),
  const span(classes: 'pill', [.text('Apache-2.0')]),
]);

/// The one-line pitch, shared by the page and the social card.
Component heroHeading({String? id}) => h1(id: id, const [
  .text('Dead code detector for '),
  span(classes: 'accent', [.text('Dart')]),
  .text(' and '),
  span(classes: 'accent', [.text('Flutter')]),
  .text('.'),
]);

/// The paragraph under the heading, shared by the page and the social card.
const heroLead =
    'Finds declarations nothing references and removes them for you. One '
    'command, no setup, backed by the Dart analysis server.';

/// The install command in a prompt-style box. The copy button is a client
/// island, so the social card leaves it out.
Component installCommandBox({bool copyButton = true}) =>
    div(classes: 'install-command', [
      const span(
        classes: 'tk-prompt',
        attributes: {'aria-hidden': 'true'},
        [.text(r'$')],
      ),
      const code([.text(installCommand)]),
      if (copyButton) const CopyButton(text: installCommand, label: 'Copy'),
    ]);
