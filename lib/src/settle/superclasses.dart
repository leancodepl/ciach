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
Future<bool> needsSuperArguments(ResolvedFiles files, Candidate cls) async =>
    (await files.of(
      cls.path,
    ))?.needSuperArguments.contains(cls.symbol.selectionRange.start) ??
    true;
