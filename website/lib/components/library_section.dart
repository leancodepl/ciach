import 'package:ciach_website/components/code_block.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/highlight.dart';
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

class LibrarySection extends StatelessComponent {
  const LibrarySection({super.key});

  @override
  Component build(BuildContext context) {
    return const Section(
      id: 'library',
      eyebrow: 'Library API',
      heading: 'Also a Dart library.',
      lead:
          'The finder behind the CLI is exported from package:ciach, so you can '
          'embed dead code detection in your own tooling, bots and dashboards.',
      children: [
        div(classes: 'library-grid', [
          CodeBlock(
            code: _library,
            language: Language.dart,
            title: 'tool/dead_code.dart',
          ),
          ul(classes: 'notes', [
            li([
              strong([Component.text('Same engine, same results. ')]),
              Component.text(
                'FinderOptions mirrors the CLI flags — root path, public or '
                'private only, kinds, includes and excludes — and the result '
                'carries every finding with file, line, kind and qualified name.',
              ),
            ]),
            li([
              strong([Component.text('Doc-only kept apart. ')]),
              Component.text(
                'Declarations referenced only from doc comments come back in '
                'their own list, so your tooling can make the same distinction '
                'the CLI does.',
              ),
            ]),
            li([
              strong([Component.text('Runs on Dart 3.10 and up. ')]),
              Component.text(
                'It analyzes with the SDK it is invoked with, so scanning code '
                'needs an SDK new enough to parse it.',
              ),
            ]),
          ]),
        ]),
      ],
    );
  }
}
