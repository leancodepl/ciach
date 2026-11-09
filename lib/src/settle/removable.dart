/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The findings a round lets `--remove` delete, by candidate index, and the
/// types they take members from.
library;

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/outline.dart';

/// The candidate indices of the findings in [candidateOf] that `--remove`
/// deletes.
Set<int> removableIndices(Map<UnusedDeclaration, int> candidateOf) => {
  for (final MapEntry(key: finding, value: i) in candidateOf.entries)
    if (!finding.removalBlocked) i,
};

/// The outlines of the candidates in [removable]. A type is emptied when
/// every member of its outline is among them; a local function in a member
/// is no member.
Set<Outline> removableOutlines(
  List<Candidate> candidates,
  Set<int> removable,
) => {for (final i in removable) candidates[i].outline};
