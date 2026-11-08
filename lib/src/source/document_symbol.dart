/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:collection/collection.dart';

/// A declaration in a file, with the declarations inside it.
///
/// The analysis server names a constructor with its class included, such as
/// `Foo` for the unnamed constructor and `Foo.named` for a named one.
final class DocumentSymbol {
  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail,
    this.children,
  });

  final String name;
  final SymbolKind kind;

  /// The declaration's code, body included.
  final Range range;

  /// The declaration's name.
  final Range selectionRange;

  /// The signature that the server shows, such as the parenthesized parameter
  /// list `(int a)` of a function.
  final String? detail;

  final List<DocumentSymbol>? children;

  @override
  bool operator ==(Object other) =>
      other is DocumentSymbol &&
      other.name == name &&
      other.kind == kind &&
      other.range == range &&
      other.selectionRange == selectionRange &&
      other.detail == detail &&
      const ListEquality<DocumentSymbol>().equals(other.children, children);

  @override
  int get hashCode => Object.hash(
    name,
    kind,
    range,
    selectionRange,
    detail,
    const ListEquality<DocumentSymbol>().hash(children),
  );

  @override
  String toString() => 'DocumentSymbol(name: $name, kind: $kind)';
}
