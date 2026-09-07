import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/demo_trigger.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _before = '''
/// Referenced from bin/app.dart.
void registerHandlers() {
  _internalHelper();
}

void _internalHelper() {}

/// Nothing calls this any more.
void danglingFunction() {}

const usedConstant = 'hello';

/// Left behind after a refactor.
const unusedConstant = 'bye';

class UnusedClass {
  void orphanMethod() {}
}''';

const _removeTranscript = r'''
$ ciach --remove
lib/greeting.dart
  9:6   function  danglingFunction  (public)
  14:7  variable  unusedConstant  (public)
  16:7  class     UnusedClass  (public)
  17:8  method    UnusedClass.orphanMethod  (public)

Found 4 unused declarations in 1 file (scanned 1 file, 8 declarations, 0.4s).
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 1 file.''';

/// The `--remove` walkthrough: the file with its dead code struck out as the
/// block scrolls into view, next to the command that did it.
class CiachDemo extends StatelessComponent {
  const CiachDemo({super.key});

  @css
  static List<StyleRule> get styles => [
    css('.ciach-grid')
        .styles(display: .grid, alignItems: .start, gap: .all(1.25.rem)),
    // Dead lines: struck and faded. Without JavaScript that is the resting
    // state; with it, `.armed` hides the strike until the block scrolls into
    // view and `.play` runs the animation once, one line after another.
    css('.ciach-before .line.dead').styles(
      position: const .relative(),
      // Size to the text so the strike covers the code, not the whole block.
      minWidth: .zero,
      opacity: 0.45,
    ),
    css('.ciach-before .line.dead::after').styles(
      content: '',
      position: .absolute(top: 50.percent, left: (-0.15).em, right: (-0.15).em),
      height: 2.px,
      pointerEvents: .none,
      backgroundColor: dangerColor,
      raw: {'transform-origin': 'left center'},
    ),
    css('.ciach-before.armed .line.dead').styles(opacity: 1),
    css('.ciach-before.armed .line.dead::after')
        .styles(raw: {'transform': 'scaleX(0)'}),
    css('.ciach-before.play .line.dead').styles(
      animation: Animation(
        name: 'dead-fade',
        duration: 500.ms,
        curve: .easeOut,
        fillMode: .forwards,
      ),
      raw: {'animation-delay': 'calc(var(--d, 0) * 140ms + 1.1s)'},
    ),
    css('.ciach-before.play .line.dead::after').styles(
      animation: Animation(
        name: 'ciach',
        duration: 300.ms,
        curve: .easeOut,
        fillMode: .forwards,
      ),
      raw: {'animation-delay': 'calc(var(--d, 0) * 140ms + 0.4s)'},
    ),
    css.keyframes('ciach', {
      'to': const Styles(raw: {'transform': 'scaleX(1)'}),
    }),
    css.keyframes('dead-fade', {'to': const Styles(opacity: 0.45)}),
    css.media(MediaQuery.all(minWidth: 760.px), [
      css('.ciach-grid').styles(raw: {'grid-template-columns': '1fr 1fr'}),
    ]),
    css.media(const MediaQuery.raw('(prefers-reduced-motion: reduce)'), [
      css('.ciach-before.armed .line.dead').styles(opacity: 0.45),
      css('.ciach-before.armed .line.dead::after').styles(transform: .none),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'remove',
      eyebrow: '--remove',
      heading: 'Report it. Or ciach it.',
      lead:
          'One flag deletes what was found, doc comments included, after '
          'showing the list and asking first.',
      children: [
        div(classes: 'ciach-grid', [
          div(id: 'remove-demo', classes: 'ciach-before', [
            CodeBlock(
              source: _before,
              language: .dart,
              title: 'lib/greeting.dart',
              deadLines: {8, 9, 13, 14, 16, 17, 18},
              copyText: '',
            ),
          ]),
          div(classes: 'ciach-terminal', [
            Terminal(transcript: _removeTranscript, title: 'ciach --remove'),
          ]),
        ]),
        DemoTrigger(targetId: 'remove-demo'),
        p(classes: 'section-more', [
          a(href: '/docs#removing', [
            .text('What --remove refuses to touch →'),
          ]),
        ]),
      ],
    );
  }
}
