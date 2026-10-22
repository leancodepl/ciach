import 'package:ciach_website/grammars/console_grammar.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_jaspr_ds/leancode_jaspr_ds.dart';

part 'hero.scopes.dart';

const heroTranscript = r'''
$ ciach
lib/greeting.dart
  15:6  function  danglingFunction  (public)
  24:7  variable  unusedConstant  (public)

lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 5 unused declarations in 2 files (scanned 13 files, 44 declarations, 0.5s)''';

/// The landing page's hero: the pitch, how to say the name, and a terminal
/// that shows a run.
class const CiachHero({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => Hero(
    heading: heroHeading,
    lead: heroLead,
    badges: heroBadges,
    afterLead: const [Pronunciation()],
    aside: const Terminal(
      transcript: heroTranscript,
      language: console,
      title: 'my_app — ciach',
      animated: true,
    ),
  );
}

/// The pills after the version, shared by the page and the social card.
const heroBadges = [Pill('Dart 3.10+'), Pill('Apache-2.0')];

/// The one-line pitch, shared by the page and the social card.
final heroHeading = [
  const Component.text('Dead code detector for '),
  span(classes: Utility.accent.name, const [.text('Dart')]),
  const Component.text(' and '),
  span(classes: Utility.accent.name, const [.text('Flutter')]),
  const Component.text('.'),
];

/// The paragraph under the heading, shared by the page and the social card.
const heroLead =
    'Finds declarations nothing references and removes them for you. One '
    'command, no setup, backed by the Dart analysis server.';

/// How to say the name, under the lead.
@scopedCss
class const Pronunciation({super.key}) extends StatelessComponent {
  static const _class = _$PronunciationScope;

  static final _root = _class.root;
  static final _ipa = _class('ipa');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        maxWidth: 38.rem,
        padding: .only(left: 1.rem),
        margin: .only(top: 1.25.rem),
        border: .only(
          left: .new(color: accentColor, width: 2.px),
        ),
        color: mutedColor,
        fontSize: 0.95.rem,
      ),
      css('& em').styles(color: textColor, fontStyle: .italic),
    ]),
    // IPA glyphs: skip the mono stack, which lacks them on Android, and
    // prefer fonts that ship the IPA block before the generic fallback.
    css(_ipa.selector).styles(
      color: text2Color,
      fontFamily: const .list([
        .new('Noto Sans'),
        .new('DejaVu Sans'),
        .new('Segoe UI'),
        .new('Helvetica Neue'),
        FontFamilies.arial,
        FontFamilies.systemUi,
        FontFamilies.sansSerif,
      ]),
      fontSize: 0.95.em,
    ),
  ];

  @override
  Component build(BuildContext context) => p(classes: _root.name, [
    const em([.text('“Ciach!”')]),
    const .text(' '),
    span(
      classes: _ipa.name,
      attributes: const {'lang': 'pl'},
      const [.text('/tɕax/')],
    ),
    const .text(' — Polish for the sound of a clean chop.'),
  ]);
}
