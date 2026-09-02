import 'package:ciach_website/components/code_block.dart';
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

const _after = '''
/// Referenced from bin/app.dart.
void registerHandlers() {
  _internalHelper();
}

void _internalHelper() {}

const usedConstant = 'hello';''';

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

class ChopDemo extends StatelessComponent {
  const ChopDemo({super.key});

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'remove',
      eyebrow: 'Ciach!',
      heading: 'And it’s gone.',
      lead:
          'ciach doesn’t stop at a report. --remove deletes every reported '
          'declaration — doc comment and annotations included — after showing '
          'you exactly what it is about to cut and asking first.',
      children: [
        div(classes: 'chop-grid', [
          CodeBlock(
            code: _before,
            language: Language.dart,
            title: 'lib/greeting.dart — before',
            deadLines: {8, 9, 13, 14, 16, 17, 18},
            copyText: '',
            classes: 'chop-before',
          ),
          div(classes: 'chop-middle', [
            Terminal(transcript: _removeTranscript, title: 'ciach --remove'),
          ]),
          CodeBlock(
            code: _after,
            language: Language.dart,
            title: 'lib/greeting.dart — after',
            copyText: '',
            classes: 'chop-after',
          ),
        ]),
        ul(classes: 'notes', [
          li([
            strong([Component.text('Asks first. ')]),
            Component.text(
              'The prompt lists what goes; --force skips it for scripts and CI. '
              'With no terminal to confirm on and no --force, nothing is removed.',
            ),
          ]),
          li([
            strong([Component.text('Conservative about what it deletes. ')]),
            Component.text(
              'An ambiguous int a = 1, b = 2; is left alone unless every '
              'declarator is unused. Run dart format afterwards.',
            ),
          ]),
          li([
            strong([
              Component.text('Report-only when removal wouldn’t compile. '),
            ]),
            Component.text(
              'The last constructor of a live class, every value of a '
              'still-used enum, or part of a primary-constructor header is '
              'flagged “unsafe to auto-remove” and skipped.',
            ),
          ]),
        ]),
      ],
    );
  }
}
