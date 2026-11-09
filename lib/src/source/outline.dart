import 'package:ciach/src/source/locations.dart';

/// A declaration in the outline of a file, with the declarations inside it.
///
/// Unlike a `DocumentSymbol`, it knows the kind that Dart gives the
/// declaration, the signature, and a [range] that includes the doc comment
/// and annotations. [codeRange] equals the document symbol's `range`,
/// [OutlineElement.range] its `selectionRange`.
final class Outline {
  const Outline({
    required this.element,
    required this.range,
    required this.codeRange,
    required this.children,
  });

  final OutlineElement element;

  /// The declaration with its doc comment and annotations.
  final Range range;

  /// The declaration without doc comment or annotations. For `int a = 1, b;`
  /// it covers only the one declarator.
  final Range codeRange;

  final List<Outline> children;

  /// Whether the declaration has a doc comment or annotations.
  bool get hasLeadingMetadata => range.start.isBefore(codeRange.start);
}

/// The declaration an [Outline] node describes.
final class OutlineElement {
  const OutlineElement({
    required this.kind,
    required this.name,
    this.range,
    this.parameters,
    this.returnType,
    this.typeParameters,
  });

  final OutlineKind kind;

  /// The name. A constructor's includes its class (`Foo.named`); an unnamed
  /// extension's is `extension on <Type>`.
  final String name;

  /// The range of the name, or of the `on` type for an unnamed extension.
  final Range? range;

  /// The parameter list as written, e.g. `(int a, {required int b})`.
  final String? parameters;

  /// The return type of a method or a function as written, empty when it has
  /// none.
  final String? returnType;

  /// The type parameters as written, e.g. `<T extends Object>`.
  final String? typeParameters;

  /// Whether this is an unnamed extension. It is named after its `on` type,
  /// without type parameters: `extension<T> on List<T>` becomes
  /// `extension on List<T>`.
  bool get isUnnamedExtension =>
      kind == .extension && name.startsWith('extension on ');

  /// Whether this declares something. The outline also lists `test(...)` and
  /// `group(...)` calls, and calls to functions annotated `@isTest` or
  /// `@isTestGroup`, which the document symbols mirror as methods.
  bool get isDeclaration => kind != .unitTestGroup && kind != .unitTestTest;
}

/// The kinds of the declarations in an outline.
enum OutlineKind {
  class$,
  classTypeAlias,
  compilationUnit,
  constructor,
  enum$,
  enumConstant,
  extension,
  extensionType,
  field,
  function,
  functionTypeAlias,
  getter,
  method,
  mixin,
  setter,
  topLevelVariable,
  typeAlias,
  unitTestGroup,
  unitTestTest,
}
