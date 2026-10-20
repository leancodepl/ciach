/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/faq.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_content/jaspr_content.dart';
import 'package:jaspr_content/theme.dart';

/// Renders the docs page's Markdown with the site's own components: its
/// sections and headings, code blocks, tables, lists, external links and the
/// `<Faq />` block.
class const DocsComponents() implements CustomComponent {
  @override
  ThemeExtension<Object?>? get theme => null;

  @override
  Component? create(Node node, NodesBuilder builder) => switch (node) {
    ElementNode(
      tag: 'section',
      attributes: {'id': final id, 'heading': final heading},
      :final children,
    ) =>
      DocSection(id: id, heading: heading, children: [builder.build(children)]),
    ElementNode(tag: 'h3', attributes: {'id': final id}) => DocHeading(
      fragment: id,
      text: node.innerText,
      subsection: true,
    ),
    ElementNode(
      tag: 'pre',
      :final attributes,
      children: [ElementNode(tag: 'code', attributes: {'class': final lang})],
    ) =>
      _codeBlock(
        node.innerText,
        language: lang.replaceFirst('language-', ''),
        metadata: attributes['data-metadata'] ?? '',
      ),
    ElementNode(tag: 'table', :final children?) => _table(children, builder),
    ElementNode(tag: 'ul', :final children) => ul(
      classes: Prose.checklist.name,
      [builder.build(children)],
    ),
    ElementNode(tag: 'a', attributes: {'href': final href}, :final children)
        when href.startsWith('http') =>
      externalLink(href, [builder.build(children)]),
    ElementNode(tag: 'Faq') => const Faq(),
    _ => null,
  };
}

/// A fenced code block. The fence's info string names the language and may
/// add `title="…"`, `copy="…"` or `copy=false`, and `wrap=false` for console
/// output whose columns must not wrap. Console output has no copy button
/// unless `copy` gives one.
Component _codeBlock(
  String source, {
  required String language,
  required String metadata,
}) {
  // The `markdown` package escapes the info string like an attribute value.
  final unescaped = metadata.replaceAllMapped(
    _entity,
    (match) => _entities[match[0]]!,
  );
  final options = {
    for (final match in _option.allMatches(unescaped))
      match.namedGroup('key')!:
          match.namedGroup('quoted') ?? match.namedGroup('bare') ?? '',
  };
  final lang = Language.values.byName(language);
  final copy = switch (options['copy']) {
    'false' => '',
    final copy? => copy,
    null => lang == .console ? '' : null,
  };
  return CodeBlock(
    source: source.endsWith('\n')
        ? source.substring(0, source.length - 1)
        : source,
    language: lang,
    title: options['title'],
    copyText: copy,
    wrap: options['wrap'] != 'false',
  );
}

final _option = RegExp(r'(?<key>\w+)(?:="(?<quoted>[^"]*)"|=(?<bare>\S+))?');

const _entities = {'&quot;': '"', '&amp;': '&', '&lt;': '<', '&gt;': '>'};
final _entity = RegExp(_entities.keys.join('|'));

/// A Markdown table as a [DocsTable]: the first cell of each row names the
/// row, and the other cells are labeled with their column on a narrow screen.
/// A table whose first column has no name is a comparison, and a cell that
/// holds only `✓` or `—` is drawn as a mark.
Component _table(List<Node> children, NodesBuilder builder) {
  final rows = [
    for (final part in children)
      if (part case ElementNode(:final children?))
        for (final row in children)
          if (row case ElementNode(tag: 'tr', :final children?))
            [for (final cell in children) cell],
  ];
  final columns = [for (final cell in rows.first) cell.innerText];
  final compare = columns.first.isEmpty;
  return div(classes: DocsTable.wrap.name, [
    table(
      classes: (DocsTable.table + (compare ? DocsTable.compare : null)).name,
      [
        thead([
          tr([
            for (final cell in rows.first)
              th(scope: 'col', [builder.build(_cellChildren(cell))]),
          ]),
        ]),
        tbody([
          for (final row in rows.skip(1))
            tr([
              th(scope: 'row', [builder.build(_cellChildren(row.first))]),
              for (final (i, cell) in row.skip(1).indexed)
                td(
                  attributes: {'data-label': columns[i + 1]},
                  [_mark(cell) ?? builder.build(_cellChildren(cell))],
                ),
            ]),
        ]),
      ],
    ),
  ]);
}

List<Node>? _cellChildren(Node cell) => switch (cell) {
  ElementNode(:final children) => children,
  _ => null,
};

Component? _mark(Node cell) => switch (cell.innerText.trim()) {
  '✓' => span(
    classes: (DocsTable.mark + DocsTable.yes).name,
    attributes: const {'aria-label': 'yes'},
    const [.text('✓')],
  ),
  '—' => span(
    classes: (DocsTable.mark + DocsTable.no).name,
    attributes: const {'aria-label': 'no'},
    const [.text('—')],
  ),
  _ => null,
};
