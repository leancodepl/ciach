/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The kind of a declaration that ciach reports. [label] is the name that
/// reports print.
enum SymbolKind {
  class$,
  mixin,
  enum$,
  enumValue,
  extension,
  extensionType,
  function,
  method,
  constructor,
  field,

  /// A getter or a setter.
  property,

  /// A top-level variable.
  variable,
  typedef;

  /// A short, lower-case label (e.g. `class`, `enum value`).
  String get label => switch (this) {
    .class$ => 'class',
    .enum$ => 'enum',
    .enumValue => 'enum value',
    .extensionType => 'extension type',
    _ => name,
  };
}
