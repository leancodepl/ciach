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
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

class const InstallSection({super.key}) extends StatelessComponent {
  @override
  Component build(BuildContext context) => const DocSection(
    id: 'install',
    heading: 'Install',
    children: [
      p([
        .text('Globally, as a native '),
        code([.text('ciach')]),
        .text(
          ' binary you can run from anywhere, or as a dev dependency '
          'that pins the version for the team and CI (then prefix '
          'commands with ',
        ),
        code([.text('dart run')]),
        .text('). Requires Dart 3.10+ and analyzes with the SDK it runs with.'),
      ]),
      CodeBlock(
        source: '$installCommand\n$devDependencyCommand',
        language: .shell,
        title: 'install',
        copyText: installCommand,
      ),
      p([
        .text('The native binary runs the analysis server with the '),
        code([.text('dart')]),
        .text(' on your '),
        code([.text('PATH')]),
        .text(' (an fvm or Flutter '),
        code([.text('dart')]),
        .text(' works too); '),
        code([.text('--dart <path>')]),
        .text(' picks another one.'),
      ]),
    ],
  );
}
