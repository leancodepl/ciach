/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/components/section.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

Component performanceSection() => DocSection(
  id: 'performance',
  heading: 'Performance',
  children: [
    p(
      rich(
        'The time goes to the analysis server: it analyzes the whole package '
        'once per run, tens of seconds for a large Flutter app, then answers '
        'one reference query per declaration, `-j` of them at a time. The '
        'lever is how much you ask for. `--no-public` is by far the cheapest '
        "mode, since a private declaration's query searches one library "
        'instead of the whole workspace, and it surfaces the '
        'highest-confidence dead code anyway. `--include` and `--exclude` '
        'narrow the scan while still counting references from everywhere.',
      ),
    ),
  ],
);
