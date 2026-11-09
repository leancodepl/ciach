import 'package:ciach/src/source/locations.dart';

/// A declaration in the outline of a file, with the declarations inside it.
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

  /// The range of the declaration's name, or of its code when it has no name
  /// range.
  Range get nameRange => element.range ?? codeRange;
}

/// The declaration an [Outline] node describes.
final class OutlineElement {
  const OutlineElement({
    required this.kind,
    required this.name,
    this.range,
    this.hasNoParameters = true,
    this.returnType,
    this.hasTypeParameters = false,
    this.isRedirectingFactory = false,
    this.isInTypeHeader = false,
    this.isFinalInstanceField = false,
    this.usesOwnValues = false,
  });

  final OutlineKind kind;

  /// The name. A constructor's includes its class (`Foo.named`); an unnamed
  /// extension's is `extension on <Type>`.
  final String name;

  /// The range of the name, or of the `on` type for an unnamed extension.
  final Range? range;

  /// Whether its parameter list is empty, or it has none, like a getter.
  final bool hasNoParameters;

  /// The return type of a method or a function as written, empty when it has
  /// none.
  final String? returnType;

  /// Whether it declares type parameters, like `<T extends Object>`.
  final bool hasTypeParameters;

  /// Whether this is a redirecting factory constructor, such as
  /// `factory Foo.a() = _A;`.
  final bool isRedirectingFactory;

  /// Whether this is declared in its type's header: a primary constructor,
  /// like `Point` in `class Point(var int x)`, or a field that a declaring
  /// parameter declares, like `x`.
  final bool isInTypeHeader;

  /// Whether this is a `final` instance field in the body of its type, which
  /// a constructor has to initialize: `final`, and neither `static` nor
  /// `const`.
  final bool isFinalInstanceField;

  /// Whether this enum reads its own `values` in its body without naming
  /// itself, as in `values.any(…)`.
  final bool usesOwnValues;

  /// Whether this is a class, enum, extension, extension type or mixin, which
  /// can declare members.
  bool get declaresMembers => const <OutlineKind>{
    .class$,
    .enum$,
    .extension,
    .extensionType,
    .mixin,
  }.contains(kind);

  /// Whether this is an unnamed extension. It is named after its `on` type,
  /// without type parameters: `extension<T> on List<T>` becomes
  /// `extension on List<T>`.
  bool get isUnnamedExtension =>
      kind == .extension && name.startsWith('extension on ');

  /// Whether this declares something. The outline also lists `test(...)` and
  /// `group(...)` calls, and calls to functions annotated `@isTest` or
  /// `@isTestGroup`.
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
