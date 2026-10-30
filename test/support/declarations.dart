/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:pro_lsp/pro_lsp.dart';

/// A symbol as the server reports it; the shape is irrelevant to the rules.
DocumentSymbol symbol(String name, {SymbolKind kind = .function}) {
  const range = Range(
    start: .new(line: 0, character: 0),
    end: .new(line: 0, character: 0),
  );
  return .new(name: name, kind: kind, range: range, selectionRange: range);
}

/// [symbol] in the file at [path], inside [container].
ResolvedDeclaration declarationAt(
  String path,
  DocumentSymbol symbol,
  String? container, {
  bool inEnum = false,
  List<ResolvedAnnotation> annotations = const [],
}) => .new(
  relativePath: path,
  symbol: symbol,
  container: container,
  inEnum: inEnum,
  annotations: annotations,
);
