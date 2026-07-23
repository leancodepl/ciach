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
  });

  final Uri uri;
  final String path;
  final DocumentSymbol symbol;
  final String? container;
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
