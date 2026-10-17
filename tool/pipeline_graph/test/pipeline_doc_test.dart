/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pipeline_graph/pipeline_doc.dart';
import 'package:test/test.dart';

void main() {
  test('`doc/pipeline_static.md` shows the calls that the source of `Ciach._run` makes', () async {
    final packageRoot = p.normalize(p.absolute('../..'));
    expect(
      File(p.join(packageRoot, pipelineDocPath)).readAsStringSync(),
      await pipelineDoc(packageRoot),
      reason:
          '$pipelineDocPath differs from the source. Run '
          '`dart run bin/pipeline_graph.dart` in tool/pipeline_graph and '
          'commit the result.',
    );
  });
}
