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

const _exportedPackages = '''
exported-packages: [packages/shared_api]''';

const _analysisRoot = r'''
$ ciach pkgs/core --analysis-root .    # scan pkgs/core, count uses from the whole repo''';

class const PackagesSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => DocSection(
    id: 'packages',
    heading: 'Packages and monorepos',
    children: [
      const h3([.text('Library packages')]),
      p(
        rich(
          'By default, ciach checks the API of every package, which suits an '
          "app. But it can't see importers outside the analysis. So list in "
          '`exported-packages` the packages that code outside the analysis '
          'imports, such as one published to pub.dev or used as a git '
          "dependency. ciach then doesn't report what other packages can "
          'import from them: the libraries under `lib/` outside `lib/src/`, '
          'what they export (`show`/`hide` respected), and the members of any '
          'type those hand out, say in a return type, a field or a supertype.',
        ),
      ),
      p(
        rich(
          "Each entry is a glob of a package directory, relative to the scanned path. `'**'` matches every package:",
        ),
      ),
      const CodeBlock(
        source: _exportedPackages,
        language: .yaml,
        title: 'ciach.yaml',
      ),
      p(rich('`-v` says which packages are left out.')),
      const h3([.text('Monorepos')]),
      p(
        rich(
          'In a monorepo where sibling packages depend on this one by `path:`, '
          'their calls are invisible, so a declaration used only from them '
          'reads as dead. `--analysis-root` widens where references are '
          'counted, and nothing else:',
        ),
      ),
      const Terminal(transcript: _analysisRoot, title: 'monorepo'),
      p(
        rich(
          'What is scanned, reported and removed, `--include`/`--exclude` and '
          '`ciach.yaml` discovery stay on the scanned package. The root must '
          'contain that package. The whole repository gets analyzed, so the '
          'run is slower.',
        ),
      ),
      p(
        rich(
          'A pub workspace needs no setting: the analysis covers every member '
          'already. Without one, `-v` notes a package in the same git '
          'repository that depends on the scanned one by `path:`, and names '
          'the `--analysis-root` that would count it.',
        ),
      ),
    ],
  );
}
