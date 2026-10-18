/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// A file path paired with a declaration name, used as a map key to look up
/// per-declaration facts gathered by the remove-safety pre-pass.
final class DeclKey {
  const DeclKey(this.path, this.name);

  final String path;
  final String name;

  @override
  bool operator ==(Object other) =>
      other is DeclKey && other.path == path && other.name == name;

  @override
  int get hashCode => Object.hash(path, name);
}

/// How a candidate's references classify it.
enum RefStatus {
  /// At least one real (non-doc-comment) reference.
  used,

  /// No real references, but at least one dartdoc `[Xxx]` comment link.
  docOnly,

  /// No references of any kind.
  unused,
}

/// A declaration to check: the symbol plus enough context to query references
/// for it and to report it later.
final class Candidate {
  const Candidate({
    required this.uri,
    required this.path,
    required this.symbol,
    required this.outline,
    required this.container,
    required this.isEnumValue,
    required this.isPreventInstantiationCtor,
    this.containerSymbol,
    this.containerOutline,
    this.isInExposedType = false,
  });

  final Uri uri;
  final String path;
  final DocumentSymbol symbol;

  final Outline outline;
  final String? container;

  /// The symbol [container] names, so a member can be placed against its type's
  /// header or body.
  final DocumentSymbol? containerSymbol;

  final Outline? containerOutline;
  final bool isEnumValue;
  final bool isPreventInstantiationCtor;

  /// `extension on T { … }`: nothing can name it, so it gets no reference
  /// query. The server calls it `extension on T`.
  bool get isUnnamedExtension => outline.element.isUnnamedExtension;

  /// `extension type Name(…)`: a type, named like a class.
  bool get isExtensionType => outline.element.kind == .extensionType;

  bool get isExtension => outline.element.kind == .extension;

  bool get isMixin => outline.element.kind == .mixin;

  bool get isExtensionMember => containerSymbol?.kind == .namespace;

  /// Whether this is a member of a private type that a public declaration
  /// of its library exposes, so other libraries can reach it: a value of the
  /// type lets them call its instance members, and a type alias names all of
  /// them.
  final bool isInExposedType;

  bool get isInUnnamedExtension =>
      containerOutline?.element.isUnnamedExtension ?? false;

  /// Whether this declaration's own name starts with `_`. An unnamed
  /// constructor's name is `new`.
  bool get hasPrivateName => isPrivateName(symbol.declarationName(container));

  /// Whether this is a member of a type that no other library can name or
  /// reach through a public declaration: one whose name starts with `_`, or
  /// an unnamed extension.
  bool get isInPrivateType =>
      !isInExposedType &&
      ((container?.let(isPrivateName) ?? false) || isInUnnamedExtension);

  /// Whether this declaration is private: by its own name, or as a member of
  /// a private type.
  bool get isPrivate => hasPrivateName || isInPrivateType;

  /// Whether this is a class, enum, mixin or extension type. Extensions are
  /// left out because code uses their members without naming them.
  bool get isType =>
      container == null && typeLikeKinds.contains(symbol.kind) && !isExtension;

  /// Whether [location], such as a definition that the server returns, points
  /// at this candidate's name.
  bool isNamedAt(Location location) =>
      SourceIndex.pathOf(location.uri) == path &&
      symbol.selectionRange.contains(location.range.start);

  /// This candidate's own `(path, name)` key.
  DeclKey get key => .new(path, symbol.name);

  /// The `(path, container)` key of this candidate's enclosing declaration,
  /// or `null` when it has no container.
  DeclKey? get containerKey => container?.let((c) => .new(path, c));
}
