/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Conversions between the `pro_lsp` types that the analysis server speaks
/// and ciach's own types, which the rest of ciach uses.
library;

import 'package:ciach/src/source/document_symbol.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/selection_range.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:pro_lsp/pro_lsp.dart' as lsp;

lsp.Position positionToLsp(Position position) =>
    .new(line: position.line, character: position.character);

Position positionFromLsp(lsp.Position position) =>
    .new(line: position.line, character: position.character);

Range rangeFromLsp(lsp.Range range) =>
    .new(start: positionFromLsp(range.start), end: positionFromLsp(range.end));

Location locationFromLsp(lsp.Location location) =>
    .new(uri: location.uri, range: rangeFromLsp(location.range));

SelectionRange selectionRangeFromLsp(lsp.SelectionRange range) => .new(
  range: rangeFromLsp(range.range),
  parent: range.parent?.let(selectionRangeFromLsp),
);

DocumentSymbol symbolFromLsp(lsp.DocumentSymbol symbol) => .new(
  name: symbol.name,
  kind: .values.byName(symbol.kind.name),
  range: rangeFromLsp(symbol.range),
  selectionRange: rangeFromLsp(symbol.selectionRange),
  detail: symbol.detail,
  children: symbol.children?.map(symbolFromLsp).toList(),
);
