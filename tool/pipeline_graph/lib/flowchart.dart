/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:pipeline_graph/call_graph.dart';

/// Returns a Mermaid flowchart of [calls], in the order in which the source
/// makes them.
String mermaidFlowchart(List<Call> calls) =>
    ['flowchart TD', ..._lines(calls, 's', '  ')].join('\n');

Iterable<String> _lines(
  List<Call> calls,
  String idPrefix,
  String indent,
) sync* {
  final ids = [for (final (i, _) in calls.indexed) '$idPrefix$i'];
  for (final (i, call) in calls.indexed) {
    final label = [
      '<code>${call.name}</code> <i>${call.directory}/</i>',
      for (final condition in call.conditions) '<i>${_escape(condition)}</i>',
    ].join('<br/>');
    if (call.children.isEmpty) {
      yield '$indent${ids[i]}["$label"]';
    } else {
      yield '${indent}subgraph ${ids[i]} ["$label"]';
      yield* _lines(call.children, '${ids[i]}_', '$indent  ');
      yield '${indent}end';
    }
  }
  if (ids.length > 1) {
    yield '$indent${ids.join(' --> ')}';
  }
}

/// Escapes [text] for a quoted Mermaid label.
String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '#quot;');
