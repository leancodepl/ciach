/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/outline.dart';

/// The nodes nested in [outline], each before the nodes nested in it.
Iterable<Outline> nestedIn(Outline outline) sync* {
  for (final child in outline.children) {
    yield child;
    yield* nestedIn(child);
  }
}
