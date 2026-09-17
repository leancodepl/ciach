import 'package:pro_lsp/pro_lsp.dart' show Range;

/// A declaration in the outline the server publishes for a file
/// (`dart/textDocument/publishOutline`).
///
/// Unlike a `DocumentSymbol`, it knows the analyzer's kind, the signature, and
/// a [range] that includes the doc comment and annotations. [codeRange] equals
/// the document symbol's `range`, [OutlineElement.range] its `selectionRange`.
final class Outline {
  const Outline({
    required this.element,
    required this.range,
    required this.codeRange,
    required this.children,
  });

  factory Outline.fromJson(Map<String, Object?> json) => Outline(
    element: OutlineElement.fromJson(json['element']! as Map<String, Object?>),
    range: Range.fromJson(json['range']! as Map<String, Object?>),
    // Older servers do not send `codeRange`.
    codeRange: switch (json['codeRange']) {
      final Map<String, Object?> codeRange => Range.fromJson(codeRange),
      _ => Range.fromJson(json['range']! as Map<String, Object?>),
    },
    children: [
      if (json['children'] case final List<Object?> children)
        for (final child in children.cast<Map<String, Object?>>())
          Outline.fromJson(child),
    ],
  );

  final OutlineElement element;

  /// The declaration with its doc comment and annotations.
  final Range range;

  /// The declaration without doc comment or annotations. For `int a = 1, b;`
  /// it covers only the one declarator.
  final Range codeRange;

  final List<Outline> children;

  /// Whether the declaration has a doc comment or annotations.
  bool get hasLeadingMetadata =>
      range.start.line < codeRange.start.line ||
      (range.start.line == codeRange.start.line &&
          range.start.character < codeRange.start.character);

  /// This node and every node nested in it.
  Iterable<Outline> get descendants sync* {
    yield this;
    for (final child in children) {
      yield* child.descendants;
    }
  }
}

/// The declaration an [Outline] node describes.
final class OutlineElement {
  const OutlineElement({
    required this.kind,
    required this.name,
    this.range,
    this.parameters,
    this.returnType,
  });

  factory OutlineElement.fromJson(Map<String, Object?> json) => OutlineElement(
    kind: OutlineKind.fromWire(json['kind'] as String? ?? ''),
    name: json['name'] as String? ?? '',
    range: switch (json['range']) {
      final Map<String, Object?> range => Range.fromJson(range),
      _ => null,
    },
    parameters: json['parameters'] as String?,
    returnType: json['returnType'] as String?,
  );

  final OutlineKind kind;

  /// The name. A constructor's includes its class (`Foo.named`); an unnamed
  /// extension's is `extension on <Type>`.
  final String name;

  /// The range of the name, or of the `on` type for an unnamed extension.
  final Range? range;

  /// The parameter list as written, e.g. `(int a, {required int b})`.
  final String? parameters;

  /// The declared return type, or a variable's type.
  final String? returnType;

  /// Whether this is an unnamed extension. The server names it after its
  /// `on` type, dropping type parameters: `extension<T> on List<T>` becomes
  /// `extension on List<T>`.
  bool get isUnnamedExtension =>
      kind == .extension && name.startsWith('extension on ');
}

/// Declaration kinds as the outline sends them.
enum OutlineKind {
  class$('CLASS'),
  compilationUnit('COMPILATION_UNIT'),
  constructor('CONSTRUCTOR'),
  enum$('ENUM'),
  enumConstant('ENUM_CONSTANT'),
  extension('EXTENSION'),
  extensionType('EXTENSION_TYPE'),
  field('FIELD'),
  function('FUNCTION'),
  functionTypeAlias('FUNCTION_TYPE_ALIAS'),
  getter('GETTER'),
  method('METHOD'),
  mixin('MIXIN'),
  setter('SETTER'),
  topLevelVariable('TOP_LEVEL_VARIABLE'),
  typeAlias('TYPE_ALIAS'),

  other('');

  const OutlineKind(this.wire);

  final String wire;

  static OutlineKind fromWire(String wire) =>
      values.firstWhere((k) => k.wire == wire, orElse: () => other);
}
