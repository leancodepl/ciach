/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/remove_safety.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:collection/collection.dart';

/// The types reported once, as report-only, instead of their members, by key,
/// with their candidate index and hint.
typedef ReportOnlyTypes = Map<DeclKey, ({int type, String hint})>;

/// Reports a type once, instead of a finding for each of its members: a dead
/// type takes its members with it, and a report-only type keeps them all.
final class WholeTypes {
  WholeTypes({required Verdict verdict}) : _verdict = verdict;

  final Verdict _verdict;

  /// Returns the types reported once, as report-only, instead of their members
  /// (see [report]):
  ///
  /// - a type that only doc comments mention, with a member in [reported];
  /// - a used enum whose values are all unused, like `enum E { a, b }` with
  ///   only `E` named, since removing the values would leave `enum E {}`.
  ///
  /// A member in [removableBefore], which an earlier round found removable,
  /// doesn't count.
  ReportOnlyTypes reportOnly(
    List<Candidate> candidates,
    List<RefStatus> statuses,
    Set<int> reported,
    Set<int> removableBefore,
    RemoveSafety safety,
  ) {
    final types = {
      for (final (i, candidate) in candidates.indexed)
        if (candidate.isType)
          if (switch ((statuses[i], candidate.kind)) {
                (.docOnly, _) => Verdict.docOnlyTypeHint,
                (.used, .enum$)
                    when safety.emptiedEnums.contains(candidate.key) =>
                  Verdict.emptiedEnumHint,
                _ => null,
              }
              case final hint?)
            candidate.key: (type: i, hint: hint),
    };
    return {
      for (final key
          in reported
              .whereNot(removableBefore.contains)
              .map((i) => candidates[i].containerKey))
        ?key: ?types[key],
    };
  }

  /// Returns [candidateOf], which maps each finding to its candidate's
  /// index, with a type reported once instead of a finding for each of its
  /// members.
  ///
  /// - A type in [reportOnlyTypes] gets one report-only finding with its hint.
  ///   Its members are not reported, so `--remove` keeps them all.
  /// - A type that is itself a removable finding, because it is unused or used
  ///   only in `with` and `implements` clauses, also removes what its members'
  ///   findings removed, like their overrides. Its members are not reported.
  ///
  /// Members of other types are still reported, and so is a member in
  /// [removableBefore], which an earlier round found removable.
  Map<UnusedDeclaration, int> report(
    Map<UnusedDeclaration, int> candidateOf,
    List<Candidate> candidates,
    ReportOnlyTypes reportOnlyTypes,
    Set<int> removableBefore,
    String rootPath,
  ) {
    Candidate candidateFor(UnusedDeclaration finding) =>
        candidates[candidateOf[finding]!];
    final deadTypes = {
      for (final finding in candidateOf.keys)
        if (candidateFor(finding) case final candidate
            when !finding.removalBlocked && candidate.container == null)
          candidate.key,
    };
    bool goesWithType(UnusedDeclaration finding) {
      final key = candidateFor(finding).containerKey;
      return deadTypes.contains(key) ||
          (reportOnlyTypes.containsKey(key) &&
              !removableBefore.contains(candidateOf[finding]));
    }

    final removalsOf = candidateOf.keys
        .where(
          (finding) =>
              deadTypes.contains(candidateFor(finding).containerKey) &&
              !finding.removalBlocked,
        )
        .groupFoldBy<DeclKey?, List<CoupledRemoval>>(
          (member) => candidateFor(member).containerKey,
          (removals, member) =>
              (removals ?? [])..addAll(member.coupledRemovals),
        );
    UnusedDeclaration withMemberRemovals(UnusedDeclaration finding) {
      final candidate = candidateFor(finding);
      return switch (removalsOf[candidate.key]) {
        final removals?
            when candidate.container == null && removals.isNotEmpty =>
          finding.copyWith(
            coupledRemovals: {...finding.coupledRemovals, ...removals}.toList(),
          ),
        _ => finding,
      };
    }

    return {
      for (final MapEntry(key: finding, value: i) in candidateOf.entries)
        if (!goesWithType(finding)) withMemberRemovals(finding): i,
      for (final (:type, :hint) in reportOnlyTypes.values)
        _verdict.finding(
          candidates[type],
          rootPath,
          removalBlocked: true,
          hint: hint,
        ): type,
    };
  }
}
