/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pipeline_graph/pipeline_doc.dart';

/// Writes `doc/pipeline_static.md` of the ciach package that holds this tool.
Future<void> main() async {
  final packageRoot = p.normalize(p.absolute('../..'));
  File(p.join(packageRoot, pipelineDocPath))
      .writeAsStringSync(await pipelineDoc(packageRoot));
}
