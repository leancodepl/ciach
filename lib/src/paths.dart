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

/// [absPath] expressed relative to [rootPath], with `/` separators — the form
/// used for a finding's and a coupled removal's `filePath`.
String relativePosix(String absPath, String rootPath) =>
    p.split(p.relative(absPath, from: rootPath)).join('/');
