/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';

/// Whether an implicit default constructor for the class [cls] would fail
/// to compile: its superclass's unnamed constructor takes required arguments,
/// or there is none. `true` when the analyzer can't resolve the file.
bool needsSuperArguments(ResolvedFiles files, Candidate cls) =>
    files
        .resolved(cls.path)
        ?.needSuperArguments
        .contains(cls.outline.nameRange.start) ??
    true;
