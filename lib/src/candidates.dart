/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

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
    required this.container,
    required this.isEnumValue,
    required this.isPreventInstantiationCtor,
    this.containerSymbol,
  });

  final Uri uri;
  final String path;
  final DocumentSymbol symbol;
  final String? container;

  /// The symbol [container] names, so a member can be placed against its type's
  /// header or body.
  final DocumentSymbol? containerSymbol;
  final bool isEnumValue;
  final bool isPreventInstantiationCtor;

  /// This candidate's own `(path, name)` key.
  DeclKey get key => DeclKey(path, symbol.name);

  /// The `(path, container)` key of this candidate's enclosing declaration,
  /// or `null` when it has no container.
  DeclKey? get containerKey => switch (container) {
    final c? => DeclKey(path, c),
    null => null,
  };
}

/// An `extension` declaration and the candidates collected from its body.
///
/// Extensions are never reference-checked themselves: the implicit `x.member()`
/// use never names the extension, so a query at its name would call every
/// extension in use dead. Instead an extension is dead when all of its members
/// are — an extension with no live member has nothing left to offer — and is
/// then reported, and removed, whole rather than left as an `extension X on T
/// {}` shell.
final class ExtensionScope {
  const ExtensionScope({
    required this.self,
    required this.members,
    required this.memberCount,
  });

  /// The extension itself, shaped as a candidate so it can be reported.
  final Candidate self;

  /// The candidates collected from the extension's members.
  final List<Candidate> members;

  /// How many members the extension declares, candidates or not. When this
  /// exceeds `members.length`, a member was skipped (public under
  /// `--no-public`, a `call` method, an operator, a kind not asked for) and
  /// the extension cannot be shown empty.
  final int memberCount;

  /// Whether every member is a candidate — the precondition for calling the
  /// extension dead from its members' verdicts.
  bool get coversEveryMember =>
      members.isNotEmpty && members.length == memberCount;
}
