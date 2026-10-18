/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/docs_table.dart';
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _comparison = [
  ('Unused private declarations', true, true),
  ('Unused public declarations', false, true),
  ('References followed across libraries', false, true),
  ('Removes what it finds', false, true),
  ('GitHub annotations on the pull request', false, true),
  ('JSON output', true, true),
];

Component _markOf(bool yes) => yes
    ? span(
        classes: (DocsTable.mark + DocsTable.yes).name,
        attributes: const {'aria-label': 'yes'},
        const [.text('✓')],
      )
    : span(
        classes: (DocsTable.mark + DocsTable.no).name,
        attributes: const {'aria-label': 'no'},
        const [.text('—')],
      );

class const ComparedSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'compared',
    heading: 'Compared with the analyzer',
    children: [
      const p([
        .text(
          'The Dart analyzer already flags unused private declarations through ',
        ),
        code([.text('unused_element')]),
        .text(
          ' and friends, one library at a time. ciach starts where that stops.',
        ),
      ]),
      div(classes: DocsTable.wrap.name, [
        table(classes: (DocsTable.table + DocsTable.compare).name, [
          const thead([
            tr([
              th(attributes: {'scope': 'col'}, [.text('')]),
              th(
                attributes: {'scope': 'col'},
                [
                  code([.text('dart analyze')]),
                ],
              ),
              th(
                attributes: {'scope': 'col'},
                [
                  code([.text('ciach')]),
                ],
              ),
            ]),
          ]),
          tbody([
            for (final (capability, analyzer, ciach) in _comparison)
              tr([
                th(attributes: const {'scope': 'row'}, [.text(capability)]),
                td(
                  attributes: const {'data-label': 'dart analyze'},
                  [_markOf(analyzer)],
                ),
                td(attributes: const {'data-label': 'ciach'}, [_markOf(ciach)]),
              ]),
          ]),
        ]),
      ]),
      const p([
        .text(
          'Both resolve references the same way, because ciach asks '
          'the analysis server. The difference is scope and the '
          'removal step. Dart Code Metrics covers unused code as well, '
          'as part of a larger commercial toolset.',
        ),
      ]),
    ],
  );
}
