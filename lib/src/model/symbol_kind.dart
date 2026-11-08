/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The kind of a declaration: one of the symbol kinds of the Language Server
/// Protocol, in its order.
///
/// The analysis server reports a Dart declaration with the closest of them,
/// such as [namespace] for an extension. ciach reports some declarations with
/// another kind than the server: a mixin with [interface$], an extension type
/// with [struct], an enum value with [enumMember] and every typedef with
/// [object]. [label] is the name that reports print.
enum SymbolKind {
  file,
  module,
  namespace,
  package,
  class$,
  method,
  property,
  field,
  constructor,
  enum$,
  interface$,
  function,
  variable,
  constant,
  string,
  number,
  boolean,
  array,
  object,
  key,
  null$,
  enumMember,
  struct,
  event,
  operator$,
  typeParameter;

  /// A short, lower-case label (e.g. `class`, `enum value`).
  String get label => switch (this) {
    .class$ => 'class',
    .enum$ => 'enum',
    // The server has no kind for a mixin and tags it as a class; ciach
    // reports it as an interface, which no Dart declaration is otherwise.
    .interface$ => 'mixin',
    .namespace => 'extension',
    .struct => 'extension type',
    .operator$ => 'operator',
    .null$ => 'null',
    .enumMember => 'enum value',
    .typeParameter => 'type parameter',
    .object => 'typedef',
    _ => name,
  };
}
