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
import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

const _library = r'''
import 'package:ciach/ciach.dart';

final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();

for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}''';

class const LibrarySection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => const DocSection(
    id: 'library',
    heading: 'Library API',
    children: [
      p([
        .text('The finder behind the CLI is exported from '),
        code([.text('package:ciach/ciach.dart')]),
        .text(
          '. Options mirror the flags; the result carries every '
          'finding with file, line, kind and qualified name, and '
          'doc-only findings in their own list.',
        ),
      ]),
      CodeBlock(
        source: _library,
        language: .dart,
        title: 'tool/dead_code.dart',
      ),
    ],
  );
}
