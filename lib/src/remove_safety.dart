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

/// Whether a class's superclass needs constructor arguments.
typedef SuperclassNeedsArguments = Future<bool> Function(Candidate cls);

/// The remove-safety pre-pass: facts gathered up front so the reporting loop
/// stays a set of cheap lookups when deciding which findings are report-only
/// (`removalBlocked`) because auto-removing them would break the build.
///
/// * [emptiedEnums] — enums every one of whose values would be removed while
///   the enum type itself stays, leaving `enum E {}` (a compile error).
/// * [blockedCtorClasses] — live classes all of whose constructors are dead:
///   removing them synthesizes an implicit default constructor that strands
///   `final` fields or calls a super constructor that needs arguments.
/// * [enumValuesIterated] — enums whose values are all reachable through
///   `.values` iteration, so a value reached only that way is used, not dead,
///   and is suppressed entirely rather than reported.
/// * [deadExtensions] — extensions nothing names and every member of which is
///   dead: reported and removed whole, like a dead class.
class RemoveSafety {
  const RemoveSafety({
    required this.emptiedEnums,
    required this.blockedCtorClasses,
    required this.enumValuesIterated,
    required this.deadExtensions,
  });

  static Future<RemoveSafety> analyze(
    SourceIndex sources,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> deadClassNames,
    SuperclassNeedsArguments superclassNeedsArguments,
  ) async {
    final tally = _Tally(sources);
    for (final (i, candidate) in candidates.indexed) {
      tally.add(candidate, refsByCandidate[i], unused: statuses[i] == .unused);
    }

    // Conservative: if the enum-type candidate is missing we cannot prove the
    // enum is itself being removed, so assume it stays and block.
    final emptiedEnums = {
      for (final key in tally.enumValues.allDead)
        if (tally.enumTypeStays[key] ?? true) key,
    };

    final blockedCtorClasses = <DeclKey>{};
    for (final key in tally.constructors.allDead) {
      // A dead class is removed whole (its constructors go with it), so its
      // constructors are never reported on their own — nothing to guard.
      if (deadClassNames[key.path]?.contains(key.name) ?? false) {
        continue;
      }
      // No declaration to inspect: block.
      final classCandidate = tally.classByKey[key];
      if (classCandidate == null ||
          sources.classHasFinalInstanceField(classCandidate) ||
          await superclassNeedsArguments(classCandidate)) {
        blockedCtorClasses.add(key);
      }
    }

    final deadExtensions = <DeclKey>{
      for (final MapEntry(:key, value: unreferenced)
          in tally.extensionUnreferenced.entries)
        if (unreferenced &&
            (tally.extensionMemberDead[key] ?? 0) ==
                tally.extensionMemberTotal[key])
          key,
    };

    return RemoveSafety(
      emptiedEnums: emptiedEnums,
      blockedCtorClasses: blockedCtorClasses,
      enumValuesIterated: tally.enumValuesIterated,
      deadExtensions: deadExtensions,
    );
  }

  final Set<DeclKey> emptiedEnums;
  final Set<DeclKey> blockedCtorClasses;
  final Set<DeclKey> enumValuesIterated;
  final Set<DeclKey> deadExtensions;
}

final class _Tally {
  _Tally(this._sources);

  final SourceIndex _sources;
  final enumTypeStays = <DeclKey, bool>{};
  final enumValues = _PartCounts();
  final enumValuesIterated = <DeclKey>{};
  final constructors = _PartCounts();
  final classByKey = <DeclKey, Candidate>{};
  final extensionUnreferenced = <DeclKey, bool>{};
  final extensionMemberTotal = <DeclKey, int>{};
  final extensionMemberDead = <DeclKey, int>{};

  void add(Candidate candidate, List<Location> refs, {required bool unused}) {
    final symbol = candidate.symbol;
    if (candidate.containerKey case final key?
        when candidate.isExtensionMember && unused) {
      extensionMemberDead.update(key, (n) => n + 1, ifAbsent: () => 1);
    }
    if (candidate.isExtension) {
      // Unnamed extensions on one type share a key; merging can only keep.
      extensionUnreferenced.update(
        candidate.key,
        (was) => was && unused,
        ifAbsent: () => unused,
      );
      // Every member counts, so one excluded by `--kinds`/`--no-public`
      // keeps the extension.
      extensionMemberTotal.update(
        candidate.key,
        (n) => n + (symbol.children?.length ?? 0),
        ifAbsent: () => symbol.children?.length ?? 0,
      );
    } else if (symbol.kind == .enum$ && !candidate.isEnumValue) {
      enumTypeStays[candidate.key] = !unused;
      if (refs.any(_sources.isDotValuesRef) ||
          _sources.enumIteratesOwnValues(candidate)) {
        enumValuesIterated.add(candidate.key);
      }
    } else if (candidate.isEnumValue) {
      enumValues.add(candidate.containerKey, dead: unused);
    } else if (symbol.kind == .class$) {
      classByKey[candidate.key] = candidate;
    } else if (symbol.kind == .constructor) {
      constructors.add(candidate.containerKey, dead: unused);
    }
  }
}

/// How many parts (enum values, constructors) each declaration has, and how
/// many of them are dead.
final class _PartCounts {
  final _total = <DeclKey, int>{};
  final _dead = <DeclKey, int>{};

  void add(DeclKey? container, {required bool dead}) {
    if (container == null) {
      return;
    }
    _total.update(container, (n) => n + 1, ifAbsent: () => 1);
    if (dead) {
      _dead.update(container, (n) => n + 1, ifAbsent: () => 1);
    }
  }

  /// The declarations every one of whose parts is dead.
  Iterable<DeclKey> get allDead =>
      _total.keys.where((key) => _dead[key] == _total[key]);
}
