/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:collection/collection.dart';
import 'package:jaspr_content/jaspr_content.dart';

/// Wraps each `h2` and the nodes up to the next one in a `section` node that
/// carries the heading's `id` and its text as `heading`, in place of the `h2`.
/// `DocsComponents` renders such a node as a `DocSection`.
class const SectionsExtension() implements PageExtension {
  @override
  Future<List<Node>> apply(Page page, List<Node> nodes) async => [
    for (final part in nodes.splitBefore(_startsSection))
      if (part case [
        ElementNode(tag: 'h2', attributes: {'id': final id}) && final heading,
        ...final rest,
      ])
        ElementNode('section', {'id': id, 'heading': heading.innerText}, rest)
      // The nodes before the first `h2`.
      else
        ...part,
  ];
}

/// Whether [node] is an `h2` with an `id`, which starts a section.
bool _startsSection(Node node) => switch (node) {
  ElementNode(tag: 'h2', attributes: {'id': _}) => true,
  _ => false,
};
