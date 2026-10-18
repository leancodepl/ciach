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
import 'package:ciach_website/site.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

Component limitationsSection() => DocSection(
  id: 'limitations',
  heading: 'Limitations',
  children: [
    const p([
      .text(
        'ciach is a static, reference-based heuristic, so review its output rather than deleting blindly:',
      ),
    ]),
    ul(classes: Prose.checklist.name, [
      li(
        rich(
          "A published package's consumers are invisible, which is why its "
          'API is left out with `exported-packages`. In a monorepo, '
          '`--analysis-root` recovers uses from a sibling package.',
        ),
      ),
      li(
        rich(
          'Reflection, dynamic invocation, and names used only from '
          'generated code you excluded are invisible to a reference search.',
        ),
      ),
      li(
        rich(
          'Other entry points, such as isolate entry points and native '
          'callbacks, have to be listed under `entry-points` or marked with '
          "`@pragma('vm:entry-point')`.",
        ),
      ),
      li(
        rich(
          "A primary constructor shares its class's references: a "
          'never-invoked one only surfaces once the class itself is dead.',
        ),
      ),
      li(
        rich(
          "A package that doesn't analyze cleanly, from a stale `pub get` or errors, yields incomplete references.",
        ),
      ),
      li([
        ...rich(
          "Bugs in the analysis server's reference search can report used "
          'code as unused, or make a query fail and land a declaration under '
          '"Not analyzed". ',
        ),
        externalLink(upstreamBugsUrl, [const .text('doc/upstream_bugs.md')]),
        const .text(
          ' lists the ones ciach has found and the SDK commits that fixed them.',
        ),
      ]),
    ]),
  ],
);
