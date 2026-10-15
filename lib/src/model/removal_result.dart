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

/// A `//` comment that `--remove` kept although it sat directly above removed
/// code: its file, relative to the root and with `/`, and its one-based line
/// in the rewritten file.
typedef LeftComment = ({String filePath, int line});

/// What `removeDeclarations` did.
class RemovalResult {
  const RemovalResult({
    required this.filesChanged,
    required this.deletedFiles,
    this.leftComments = const [],
    this.removedRanges = 0,
  });

  /// Files declarations were removed from, deleted ones included.
  final int filesChanged;

  final List<DeletedFile> deletedFiles;

  /// The `//` comments kept directly above removed code, which may have been
  /// about it. Sorted by file, then line.
  final List<LeftComment> leftComments;

  /// How many empty ranges were removed, with both their comments.
  final int removedRanges;
}
