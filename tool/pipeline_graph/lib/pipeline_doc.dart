/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:path/path.dart' as p;
import 'package:pipeline_graph/call_graph.dart';
import 'package:pipeline_graph/flowchart.dart';

/// Where [pipelineDoc] goes, relative to the ciach package.
const pipelineDocPath = 'doc/pipeline_static.md';

/// Returns the contents of [pipelineDocPath] for the ciach package at
/// [packageRoot].
Future<String> pipelineDoc(String packageRoot) async {
  final calls = await callsFrom(
    packageRoot: packageRoot,
    path: p.join(packageRoot, 'lib', 'src', 'finder.dart'),
    className: 'Ciach',
    methodName: '_run',
  );
  return '''
<!-- Written by tool/pipeline_graph; rewrite it with
     `dart run bin/pipeline_graph.dart` in tool/pipeline_graph. -->

# The calls of a scan

Each box is a call that `Ciach._run` in `lib/src/finder.dart` makes into
${pipelineDirectories.map((d) => '`$d/`').join(', ')}, read from the source
without running it. A box that holds other boxes lists the calls that its
callee makes, up to $maxDepth files deep, and a note under a call gives the
conditions around it.

```mermaid
${mermaidFlowchart(calls)}
```
''';
}
