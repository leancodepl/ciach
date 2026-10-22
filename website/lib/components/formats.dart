import 'package:ciach_website/grammars/console_grammar.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:leancode_jaspr_ds/leancode_jaspr_ds.dart';

const _textOutput = '''
lib/orphans.dart
  8:7   class        UnusedClass  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 3 unused declarations in 1 file (scanned 1 file, 6 declarations, 1.3s)''';

const _jsonOutput = '''
{
  "summary": {
    "filesScanned": 1,
    "declarationsChecked": 6,
    "unusedCount": 3,
    "docOnlyCount": 0,
    "emptyFileCount": 0,
    "emptyVariantCount": 0,
    "elapsedMs": 1317
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
    },
    {
      "name": "FullyDeadClass",
      "qualifiedName": "FullyDeadClass",
      "kind": "class",
      "file": "lib/orphans.dart",
      "line": 22,
      "column": 7,
      "isPrivate": false
    },
    {
      "name": "new",
      "qualifiedName": "ReferencedAsTypeOnly.new",
      "kind": "constructor",
      "file": "lib/orphans.dart",
      "line": 31,
      "column": 3,
      "isPrivate": false,
      "container": "ReferencedAsTypeOnly"
    }
  ],
  "docOnly": [],
  "emptyFiles": [],
  "emptyVariants": [],
  "emptiedContainers": [
    {
      "filePath": "lib/orphans.dart",
      "name": "ReferencedAsTypeOnly"
    }
  ],
  "warnings": [],
  "problems": []
}''';

const _githubOutput = """
::warning file=lib/orphans.dart,line=8,col=7,title=Unused declaration::Unused class 'UnusedClass'
::warning file=lib/orphans.dart,line=22,col=7,title=Unused declaration::Unused class 'FullyDeadClass'
::warning file=lib/orphans.dart,line=31,col=3,title=Unused declaration::Unused constructor 'ReferencedAsTypeOnly.new'""";

class const _Format(
  final String id,
  final String command,
  final String output,
  final Language language,
);

const _formats = [
  _Format('text', 'ciach', _textOutput, console),
  _Format('json', 'ciach -f json', _jsonOutput, .json),
  _Format('github', 'ciach -f github', _githubOutput, console),
];

/// The three output formats, one sample each, in a [Tabs] switcher.
class const OutputFormats({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) {
    return Section(
      id: 'formats',
      eyebrow: 'Output',
      heading: 'Speaks human, machine and GitHub.',
      lead:
          'Pick the format with `-f`: `text`, `json` and `github` here, `azure`, '
          '`teamcity`, `sarif`, `checkstyle` and `gitlab` for other services. Exit '
          'codes are the same in every one.',
      children: [
        Tabs(
          name: 'format',
          groupLabel: 'Output format',
          tabs: [
            for (final format in _formats)
              .new(format.id, code([.text('-f ${format.id}')]), [
                CodeBlock(
                  source: format.output,
                  language: format.language,
                  title: r'$ ' + format.command,
                  copyText: format.command,
                ),
              ]),
          ],
        ),
        p(classes: Prose.more.name, const [
          a(href: '/docs#ci', [
            .text('The other services and report formats →'),
          ]),
        ]),
      ],
    );
  }
}
