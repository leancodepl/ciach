/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The findings a round lets `--remove` delete, by candidate index, and the
/// types they take members from.
library;

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:collection/collection.dart';

/// The candidate indices of the findings in [candidateOf] that `--remove`
/// deletes.
Set<int> removableIndices(Map<UnusedDeclaration, int> candidateOf) => {
  for (final MapEntry(key: finding, value: i) in candidateOf.entries)
    if (!finding.removalBlocked) i,
};

/// Returns, by key, each class, mixin or extension with a member in
/// [removable]: its outline, and how many of its members are in [removable].
Map<DeclKey, ({Outline? outline, int removable})> removableMembers(
  List<Candidate> candidates,
  Set<int> removable,
) => {
  for (final MapEntry(:key, value: members)
      in removable
          .map((i) => candidates[i])
          .groupListsBy((candidate) => candidate.containerKey)
          .entries)
    ?key: (outline: members.first.containerOutline, removable: members.length),
};
