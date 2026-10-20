/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:jaspr_content/jaspr_content.dart';

/// Wraps each `h2` and the nodes up to the next one in a `section` node that
/// carries the heading's `id` and its text as `heading`, in place of the `h2`.
/// `DocsComponents` renders such a node as a `DocSection`.
class const SectionsExtension() implements PageExtension {
  @override
  Future<List<Node>> apply(Page page, List<Node> nodes) async {
    final sections = <Node>[];
    var current = <Node>[];
    Map<String, String>? attributes;

    void close() {
      if (attributes case final attributes?) {
        sections.add(ElementNode('section', attributes, current));
      } else {
        sections.addAll(current);
      }
      current = [];
    }

    for (final node in nodes) {
      if (node case ElementNode(tag: 'h2', attributes: {'id': final id})) {
        close();
        attributes = {'id': id, 'heading': node.innerText};
      } else {
        current.add(node);
      }
    }
    close();
    return sections;
  }
}
