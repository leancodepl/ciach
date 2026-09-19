/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:path/path.dart' as p;

extension AbsolutePath on String {
  /// This path made absolute and normalized.
  String get absoluteNormalized => p.normalize(p.absolute(this));
}

/// [absPath] expressed relative to [rootPath], with `/` separators — the form
/// used for a finding's and a coupled removal's `filePath`.
String relativePosix(String absPath, String rootPath) =>
    p.split(p.relative(absPath, from: rootPath)).join('/');

/// A usage site's path for display: relative to [rootPath] inside the scanned
/// package, to [analysisRoot] outside it — `pkgs/app/lib/x.dart`, not
/// `../app/lib/x.dart`.
String relativeUsagePosix(
  String absPath,
  String rootPath,
  String analysisRoot,
) => p.isWithin(rootPath, absPath)
    ? relativePosix(absPath, rootPath)
    : relativePosix(absPath, analysisRoot);

/// Whether [analysisRoot] contains [rootPath] — the invariant a widened
/// analysis root has to meet. Both must be absolute and normalized.
bool analysisRootContains(String analysisRoot, String rootPath) =>
    p.equals(analysisRoot, rootPath) || p.isWithin(analysisRoot, rootPath);
