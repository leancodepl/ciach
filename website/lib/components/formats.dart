import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'formats.scopes.dart';

const _textOutput = '''
lib/orphans.dart
  8:7   class        UnusedClass  (public)
  10:8  method       UnusedClass.orphanMethod  (public)
  22:7  class        FullyDeadClass  (public)
  31:3  constructor  ReferencedAsTypeOnly.new  (public)

Found 4 unused declarations in 1 file (scanned 1 file, 6 declarations, 0.7s)''';

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
  "docOnly": [],
  "warnings": [],
  "problems": []
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
  _Format('text', 'ciach', _textOutput, .console),
  _Format('json', 'ciach -f json', _jsonOutput, .json),
  _Format('github', 'ciach -f github', _githubOutput, .console),
];

/// Output-format switcher built from radio inputs and CSS alone, so all three
/// samples are in the HTML for crawlers and the page needs no script for it.
@scopedCss
class OutputFormats extends StatelessComponent {
  const OutputFormats({super.key});

  static const _class = _$OutputFormatsScope;

  static final _tabs = _class('tabs');
  static final _input = _class('input');
  static final _list = _class('list');
  static final _tab = _class('tab');
  static final _panels = _class('panels');
  static final _panel = _class('panel');

  /// The panel of the format [id], on top of [_panel].
  static ClassName _panelFor(String id) => _class('panel-$id');

  @css
  static List<StyleRule> get styles => [
    css(_tabs.selector).styles(position: const .relative()),
    css(_input.selector).styles(
      position: const .absolute(),
      width: 1.px,
      height: 1.px,
      margin: .all((-1).px),
      opacity: 0,
      overflow: .hidden,
      raw: {'clip': 'rect(0 0 0 0)'},
    ),
    css(_list.selector).styles(
      display: .inlineFlex,
      padding: .all(0.3.rem),
      margin: .only(bottom: 1.25.rem),
      border: hairline(borderColor),
      radius: .circular(999.px),
      gap: .all(0.25.rem),
      backgroundColor: surfaceColor,
    ),
    css(_tab.selector, [
      css('&').styles(
        padding: .symmetric(vertical: 0.5.rem, horizontal: 1.rem),
        radius: .circular(999.px),
        cursor: .pointer,
        transition: .combine([
          .new('background-color', duration: 150.ms, curve: .ease),
          .new('color', duration: 150.ms, curve: .ease),
        ]),
        color: text2Color,
      ),
      css('& code').styles(fontSize: 0.85.rem),
      css('&:hover').styles(color: textColor),
    ]),
    // A panel may hold a wide code sample, which scrolls instead.
    css(_panel.selector).styles(display: .none, minWidth: .zero),
    // The checked radio selects its tab and panel, so the tabs need no script.
    css(
      _selectors(
        (id) => "#format-$id:checked ~ ${_list.selector} [for='format-$id']",
      ),
    ).styles(color: accentInkColor, backgroundColor: accentColor),
    css(
      _selectors(
        (id) =>
            '#format-$id:checked ~ ${_panels.selector} '
            '${_panelFor(id).selector}',
      ),
    ).styles(display: .block),
    css(
      _selectors(
        (id) =>
            '#format-$id:focus-visible ~ ${_list.selector} '
            "[for='format-$id']",
      ),
    ).styles(
      outline: .new(
        color: accentColor,
        style: .solid,
        width: .new(2.px),
        offset: 2.px,
      ),
    ),
  ];

  static String _selectors(String Function(String id) selector) =>
      _formats.map((format) => selector(format.id)).join(', ');

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'formats',
      eyebrow: 'Output',
      heading: 'Speaks human, machine and GitHub.',
      lead: 'Pick the format with `-f`. Exit codes are the same in every one.',
      children: [
        div(classes: _tabs.name, [
          for (final (index, format) in _formats.indexed)
            input(
              type: .radio,
              name: 'format',
              id: 'format-${format.id}',
              classes: _input.name,
              checked: index == 0 ? true : null,
            ),
          div(
            classes: _list.name,
            // The switch is radio inputs with labels, which is what assistive
            // technology already sees; a tablist would promise tab roles the
            // labels do not have.
            attributes: const {'role': 'group', 'aria-label': 'Output format'},
            [
              for (final format in _formats)
                label(
                  classes: _tab.name,
                  attributes: {'for': 'format-${format.id}'},
                  [
                    code([.text('-f ${format.id}')]),
                  ],
                ),
            ],
          ),
          div(classes: _panels.name, [
            for (final format in _formats)
              div(classes: (_panel + _panelFor(format.id)).name, [
                CodeBlock(
                  source: format.output,
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
