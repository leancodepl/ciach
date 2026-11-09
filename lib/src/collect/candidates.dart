/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';

/// A file path paired with a declaration name, the key of a declaration in
/// maps and sets.
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

/// A declaration to check: its outline node plus enough context to look up
/// its references and to report it later.
final class Candidate {
  const Candidate({
    required this.path,
    required this.file,
    required this.outline,
    this.containerOutline,
  });

  final String path;

  /// The file at [path], as the analyzer resolves it.
  final ResolvedFile file;

  final Outline outline;

  /// The type that declares this member, so a member can be placed against
  /// its type's header or body, or `null` at the top level.
  final Outline? containerOutline;

  String get name => outline.element.name;

  OutlineKind get kind => outline.element.kind;

  /// The name of [containerOutline].
  String? get container => containerOutline?.element.name;

  /// The kind that reports print. A candidate is always a declaration, so it
  /// has one.
  SymbolKind get reportedKind => outline.element.reportedKind!;

  bool get isEnumValue => kind == .enumConstant;

  /// Whether this is the classic prevent-instantiation marker: a class's
  /// sole, zero-parameter private constructor (`Foo._();`).
  bool get isPreventInstantiationCtor =>
      outline.element.isPrivateConstructor &&
      outline.element.hasNoParameters &&
      containerOutline?.children
              .where((member) => member.element.kind == .constructor)
              .length ==
          1;

  /// `extension on T { … }`: nothing can name it, so its references aren't
  /// looked up. Its outline names it `extension on T`.
  bool get isUnnamedExtension => outline.element.isUnnamedExtension;

  /// `extension type Name(…)`: a type, named like a class.
  bool get isExtensionType => kind == .extensionType;

  bool get isExtension => kind == .extension;

  /// Whether this is a class, a mixin application class or a mixin.
  bool get isClassOrMixin =>
      const <OutlineKind>{.class$, .classTypeAlias, .mixin}.contains(kind);

  /// Whether this is a member of an extension or an extension type, whose
  /// members are resolved statically.
  bool get isExtensionMember => const <OutlineKind>{
    .extension,
    .extensionType,
  }.contains(containerOutline?.element.kind);

  bool get isInUnnamedExtension =>
      containerOutline?.element.isUnnamedExtension ?? false;

  /// Whether this is an unnamed extension or one of its members, which no
  /// other library can use.
  bool get belongsToUnnamedExtension =>
      isUnnamedExtension || isInUnnamedExtension;

  /// Whether this is a class, enum, mixin or extension type. Extensions are
  /// left out because code uses their members without naming them.
  bool get isType =>
      container == null &&
      (isClassOrMixin || kind == .enum$ || isExtensionType);

  /// This candidate's own `(path, name)` key.
  DeclKey get key => .new(path, name);

  /// The zero-based line and column of this declaration's name.
  ({int line, int column}) get namePosition =>
      file.positionOf(outline.nameRange.start);

  /// The `(path, container)` key of this candidate's enclosing declaration,
  /// or `null` when it has no container.
  DeclKey? get containerKey => container?.let((c) => .new(path, c));
}
