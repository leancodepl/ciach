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

/// A declaration to check: the symbol plus enough context to query references
/// for it and to report it later.
typedef Candidate = ({
  Uri uri,
  String path,
  DocumentSymbol symbol,
  String? container,
  bool isEnumValue,
  bool isPreventInstantiationCtor,
});

/// A file path paired with a declaration name, used as a map key to look up
/// per-declaration facts gathered by the remove-safety pre-pass.
typedef DeclKey = ({String path, String name});

/// How a candidate's references classify it.
enum RefStatus {
  /// At least one real (non-doc-comment) reference.
  used,

  /// No real references, but at least one dartdoc `[Xxx]` comment link.
  docOnly,

  /// No references of any kind.
  unused,
}

/// The map key pairing a file [path] with a declaration [name].
DeclKey declKey(String path, String name) => (path: path, name: name);

extension CandidateKeys on Candidate {
  /// This candidate's own `(path, name)` key.
  DeclKey get key => (path: path, name: symbol.name);

  /// The `(path, container)` key of this candidate's enclosing declaration,
  /// or `null` when it has no container.
  DeclKey? get containerKey => switch (container) {
    final c? => (path: path, name: c),
    null => null,
  };
}
