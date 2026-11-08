/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/locations.dart';

/// The [range] of a syntax node, and the [parent] that encloses it, up to the
/// whole file. The innermost node holds the position that it was asked for.
final class SelectionRange {
  const SelectionRange({required this.range, this.parent});

  final Range range;
  final SelectionRange? parent;

  @override
  bool operator ==(Object other) =>
      other is SelectionRange && other.range == range && other.parent == parent;

  @override
  int get hashCode => Object.hash(range, parent);

  @override
  String toString() => 'SelectionRange(range: $range, parent: $parent)';
}
