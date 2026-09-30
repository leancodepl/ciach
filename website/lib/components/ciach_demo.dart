import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/demo_trigger.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'ciach_demo.scopes.dart';

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

Found 4 unused declarations in 1 file (scanned 1 file, 8 declarations, 0.4s)
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 1 file.''';

/// The `--remove` walkthrough: the file with its dead code struck out as the
/// block scrolls into view, next to the command that did it.
@scopedCss
class CiachDemo extends StatelessComponent {
  const CiachDemo({super.key});

  static const _class = _$CiachDemoScope;

  static final _grid = _class('grid');
  static final _sample = _class('sample');
  static final _terminal = _class('terminal');

  /// A dead line of the sample.
  static final _deadLine = Highlight.line + Highlight.dead;

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(display: .grid, alignItems: .start, gap: .all(1.25.rem)),
      shrinkableChildren(),
      css.media(.all(minWidth: 760.px), [
        css('&').styles(raw: {'grid-template-columns': '1fr 1fr'}),
      ]),
    ]),
    // Dead lines: struck and faded. Without JavaScript that is the resting
    // state; with it, [DemoTrigger.armed] hides the strike until the block
    // scrolls into view and [DemoTrigger.play] runs the animation once, one
    // line after another.
    css(_sample.selector, [
      css('& ${_deadLine.selector}', [
        css('&').styles(
          position: const .relative(),
          // Size to the text so the strike covers the code, not the whole
          // block.
          minWidth: .zero,
          opacity: 0.45,
        ),
        css('&::after').styles(
          content: '',
          position: .absolute(
            top: 50.percent,
            left: (-0.15).em,
            right: (-0.15).em,
          ),
          height: 2.px,
          pointerEvents: .none,
          backgroundColor: dangerColor,
          raw: {'transform-origin': 'left center'},
        ),
      ]),
      css('&${DemoTrigger.armed.selector} ${_deadLine.selector}', [
        css('&').styles(opacity: 1),
        css('&::after').styles(raw: {'transform': 'scaleX(0)'}),
        css.media(reducedMotion, [
          css('&').styles(opacity: 0.45),
          css('&::after').styles(transform: .none),
        ]),
      ]),
      css('&${DemoTrigger.play.selector} ${_deadLine.selector}', [
        css('&').styles(
          animation: .new(
            name: 'dead-fade',
            duration: 500.ms,
            curve: .easeOut,
            fillMode: .forwards,
          ),
          raw: {'animation-delay': 'calc(var(--d, 0) * 140ms + 1.1s)'},
        ),
        css('&::after').styles(
          animation: .new(
            name: 'ciach',
            duration: 300.ms,
            curve: .easeOut,
            fillMode: .forwards,
          ),
          raw: {'animation-delay': 'calc(var(--d, 0) * 140ms + 0.4s)'},
        ),
      ]),
    ]),
    css.keyframes('ciach', {
      'to': const .new(raw: {'transform': 'scaleX(1)'}),
    }),
    css.keyframes('dead-fade', {'to': const .new(opacity: 0.45)}),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'remove',
      eyebrow: '--remove',
      heading: 'Report it. Or ciach it.',
      lead:
          'One flag deletes what was found, doc comments included, after '
          'showing the list and asking first.',
      children: [
        div(classes: _grid.name, [
          div(id: 'remove-demo', classes: _sample.name, const [
            CodeBlock(
              source: _before,
              language: .dart,
              title: 'lib/greeting.dart',
              deadLines: {8, 9, 13, 14, 16, 17, 18},
              copyText: '',
            ),
          ]),
          div(classes: _terminal.name, const [
            Terminal(transcript: _removeTranscript, title: 'ciach --remove'),
          ]),
        ]),
        const DemoTrigger(targetId: 'remove-demo'),
        p(classes: Prose.more.name, const [
          a(href: '/docs#removing', [
            .text('What --remove refuses to touch →'),
          ]),
        ]),
      ],
    );
  }
}
