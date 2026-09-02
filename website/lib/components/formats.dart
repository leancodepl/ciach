import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _textOutput = '''
lib/orphans.dart
  8:7   class        UnusedClass  (public)
  10:8  method       UnusedClass.orphanMethod  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 4 unused declarations in 1 file (scanned 1 file, 6 declarations, 0.7s).''';

const _jsonOutput = '''
{
  "summary": {
    "filesScanned": 1,
    "declarationsChecked": 6,
    "unusedCount": 4,
    "docOnlyCount": 0,
    "elapsedMs": 729
  },
  "unused": [
    {
      "name": "UnusedClass",
      "qualifiedName": "UnusedClass",
      "kind": "class",
      "file": "lib/orphans.dart",
      "line": 8,
      "column": 7,
      "isPrivate": false
    }
  ],
  "docOnly": []
}''';

const _githubOutput = '''
::warning file=lib/orphans.dart,line=8,col=7,title=Unused declaration::Unused class 'UnusedClass'
::warning file=lib/orphans.dart,line=10,col=8,title=Unused declaration::Unused method 'UnusedClass.orphanMethod'
::warning file=lib/orphans.dart,line=22,col=7,title=Unused declaration::Unused class 'FullyDeadClass'
::notice file=lib/greeting.dart,line=41,col=6,title=Referenced only from a doc comment::function '_docOnlyMentioned' has no code references, only a dartdoc link''';

class _Format {
  const _Format(this.id, this.command, this.output, this.language);

  final String id;
  final String command;
  final String output;
  final Language language;
}

const _formats = [
  _Format('text', 'ciach', _textOutput, Language.console),
  _Format('json', 'ciach -f json', _jsonOutput, Language.json),
  _Format('github', 'ciach -f github', _githubOutput, Language.console),
];

/// Output-format switcher built from radio inputs and CSS alone, so all three
/// samples are in the HTML for crawlers and the page needs no script for it.
class OutputFormats extends StatelessComponent {
  const OutputFormats({super.key});

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'formats',
      eyebrow: 'Output',
      heading: 'Speaks human, machine and GitHub.',
      lead: 'Pick the format with `-f`. Exit codes are the same in every one.',
      children: [
        div(classes: 'tabs', [
          for (final (index, format) in _formats.indexed)
            Component.element(
              tag: 'input',
              attributes: {
                'type': 'radio',
                'name': 'format',
                'id': 'format-${format.id}',
                'class': 'tab-input',
                if (index == 0) 'checked': '',
              },
            ),
          div(
            classes: 'tab-list',
            attributes: const {
              'role': 'tablist',
              'aria-label': 'Output format',
            },
            [
              for (final format in _formats)
                label(
                  classes: 'tab',
                  attributes: {'for': 'format-${format.id}'},
                  [
                    code([Component.text('-f ${format.id}')]),
                  ],
                ),
            ],
          ),
          div(classes: 'tab-panels', [
            for (final format in _formats)
              div(classes: 'tab-panel tab-panel-${format.id}', [
                CodeBlock(
                  code: format.output,
                  language: format.language,
                  title: r'$ ' + format.command,
                  copyText: format.command,
                ),
              ]),
          ]),
        ]),
      ],
    );
  }
}
