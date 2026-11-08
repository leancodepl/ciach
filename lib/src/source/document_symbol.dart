/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:collection/collection.dart';

/// A declaration in a file, with the declarations inside it.
///
/// A constructor is named with its class included, such as `Foo` for the
/// unnamed constructor and `Foo.named` for a named one.
final class DocumentSymbol {
  const DocumentSymbol({
    required this.name,
    required this.kind,
    required this.range,
    required this.selectionRange,
    this.detail,
    this.children = const [],
  });

  /// Returns the symbol of the declaration [outline], with the kind that the
  /// analysis server gives it: a mixin and a function type alias are classes,
  /// an enum value is an enum, and any other type alias is an object.
  DocumentSymbol.fromOutline(Outline outline)
    : this(
        name: outline.element.name,
        kind: switch (outline.element.kind) {
          .class$ || .classTypeAlias || .functionTypeAlias || .mixin => .class$,
          .compilationUnit => .file,
          .constructor => .constructor,
          .enum$ || .enumConstant => .enum$,
          .extension || .extensionType => .namespace,
          .field => .field,
          .function => .function,
          .getter || .setter => .property,
          .method || .unitTestGroup || .unitTestTest => .method,
          .topLevelVariable => .variable,
          .typeAlias => .object,
        },
        range: outline.codeRange,
        selectionRange: outline.element.range ?? outline.codeRange,
        detail: outline.element.parameters,
        children: [for (final child in outline.children) .fromOutline(child)],
      );

  final String name;
  final SymbolKind kind;

  /// The declaration's code, body included.
  final Range range;

  /// The declaration's name.
  final Range selectionRange;

  /// The parameter list of a constructor, method or function as written, such
  /// as `(int a)`.
  final String? detail;

  final List<DocumentSymbol> children;

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
