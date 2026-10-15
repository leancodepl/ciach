/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// What `removeDeclarations` did, and what it touched.
library;

/// A file `--remove` deleted, and the files unlinked from it. Root-relative
/// `/`-paths.
typedef DeletedFile = ({String filePath, List<String> unlinkedFrom});

/// What `removeDeclarations` did.
class RemovalResult {
  const RemovalResult({required this.filesChanged, required this.deletedFiles});

  /// Files declarations were removed from, deleted ones included.
  final int filesChanged;

  final List<DeletedFile> deletedFiles;
}
