/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:ciach/src/source/locations.dart';

extension EntityRanges on SyntacticEntity {
  /// The range of this token or syntax node.
  Range get range => .new(start: offset, end: end);
}
