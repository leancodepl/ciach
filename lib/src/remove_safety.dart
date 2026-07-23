/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// The remove-safety pre-pass: facts gathered up front so the reporting loop
/// stays a set of cheap lookups when deciding which findings are report-only
/// (`removalBlocked`) because auto-removing them would break the build.
///
/// * [emptiedEnums] — enums every one of whose values would be removed while
///   the enum type is still referenced, leaving `enum E {}` (a compile error).
/// * [blockedCtorClasses] — live classes all of whose constructors are dead:
///   removing them synthesizes an implicit default constructor that strands
///   `final` fields or breaks super-constructor forwarding.
/// * [enumValuesIterated] — enums whose values are all reachable through
///   `.values` iteration, so a value reached only that way is used, not dead,
///   and is suppressed entirely rather than reported.
class RemoveSafety {
  const RemoveSafety({
    required this.emptiedEnums,
    required this.blockedCtorClasses,
    required this.enumValuesIterated,
  });

  factory RemoveSafety.analyze(
    SourceIndex sources,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> deadClassNames,
  ) {
    final enumTypeHasRef = <DeclKey, bool>{};
    final enumValueTotal = <DeclKey, int>{};
    final enumValueDead = <DeclKey, int>{};
    final enumValuesIterated = <DeclKey>{};
    final ctorTotal = <DeclKey, int>{};
    final ctorDead = <DeclKey, int>{};
    final ctorForwardsSuper = <DeclKey, bool>{};
    final classByKey = <DeclKey, Candidate>{};

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final symbol = candidate.symbol;
      final unused = statuses[i] == .unused;
      if (symbol.kind == .enum$ && !candidate.isEnumValue) {
        enumTypeHasRef[candidate.key] = refsByCandidate[i].isNotEmpty;
        if (refsByCandidate[i].any(sources.isDotValuesRef) ||
            sources.enumIteratesOwnValues(candidate)) {
          enumValuesIterated.add(candidate.key);
        }
      } else if (candidate.isEnumValue) {
        if (candidate.containerKey case final key?) {
          enumValueTotal.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (unused) {
            enumValueDead.update(key, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      } else if (symbol.kind == .class$) {
        classByKey[candidate.key] = candidate;
      } else if (symbol.kind == .constructor) {
        if (candidate.containerKey case final key?) {
          ctorTotal.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (unused) {
            ctorDead.update(key, (n) => n + 1, ifAbsent: () => 1);
            if (sources.ctorForwardsSuper(candidate)) {
              ctorForwardsSuper[key] = true;
            }
          }
        }
      }
    }

    final emptiedEnums = <DeclKey>{};
    for (final MapEntry(:key, value: total) in enumValueTotal.entries) {
      final dead = enumValueDead[key] ?? 0;
      if (dead == 0 || dead != total) {
        continue;
      }
      // Conservative: if the enum-type candidate is missing we cannot prove the
      // enum is itself being removed, so assume it stays and block.
      if (enumTypeHasRef[key] ?? true) {
        emptiedEnums.add(key);
      }
    }

    final blockedCtorClasses = <DeclKey>{};
    for (final MapEntry(:key, value: total) in ctorTotal.entries) {
      final dead = ctorDead[key] ?? 0;
      if (dead == 0 || dead != total) {
        continue;
      }
      // A dead class is removed whole (its constructors go with it), so its
      // constructors are never reported on their own — nothing to guard.
      if (deadClassNames[key.path]?.contains(key.name) ?? false) {
        continue;
      }
      final classCandidate = classByKey[key];
      final hasFinalField =
          classCandidate != null &&
          sources.classHasFinalInstanceField(classCandidate);
      if (hasFinalField || (ctorForwardsSuper[key] ?? false)) {
        blockedCtorClasses.add(key);
      }
    }

    return RemoveSafety(
      emptiedEnums: emptiedEnums,
      blockedCtorClasses: blockedCtorClasses,
      enumValuesIterated: enumValuesIterated,
    );
  }

  final Set<DeclKey> emptiedEnums;
  final Set<DeclKey> blockedCtorClasses;
  final Set<DeclKey> enumValuesIterated;
}
