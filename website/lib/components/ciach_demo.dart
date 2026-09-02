import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/demo_trigger.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
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
              code: _before,
              language: Language.dart,
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
            Component.text('What --remove refuses to touch →'),
          ]),
        ]),
      ],
    );
  }
}
