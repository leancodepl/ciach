/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:collection/collection.dart';

/// Whether a class's superclass needs constructor arguments.
typedef SuperclassNeedsArguments = bool Function(Candidate cls);

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
/// * [extensionsWithLiveMembers] — extensions with a member that isn't dead,
///   which keeps the extension in use, also when nothing names it.
/// * [deadExtensions] — extensions nothing names and every member of which is
///   dead: reported and removed whole, like a dead class.
class RemoveSafety {
  const RemoveSafety({
    required this.emptiedEnums,
    required this.blockedCtorClasses,
    required this.enumValuesIterated,
    required this.extensionsWithLiveMembers,
    required this.deadExtensions,
  });

  static RemoveSafety analyze(
    FileSyntax syntax,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> deadClassNames,
    SuperclassNeedsArguments superclassNeedsArguments,
  ) {
    final dead = {
      for (final (i, candidate) in candidates.indexed)
        if (statuses[i] == .unused) candidate,
    };

    final enumStays = {
      for (final candidate in candidates)
        if (candidate.kind == .enum$) candidate.key: !dead.contains(candidate),
    };
    final emptiedEnums = {
      for (final key in _allPartsDead(
        candidates.where((candidate) => candidate.isEnumValue),
        dead,
      ))
        // Conservative: if the enum-type candidate is missing we cannot prove
        // the enum is itself being removed, so assume it stays and block.
        if (enumStays[key] ?? true) key,
    };

    final classes = {
      for (final candidate in candidates)
        if (candidate.isClassOrMixin) candidate.key: candidate,
    };
    bool needsConstructor(Candidate? cls) =>
        // No declaration to inspect: block.
        cls == null ||
        cls.outline.children.any(
          (member) => member.element.isFinalInstanceField,
        ) ||
        superclassNeedsArguments(cls);
    final blockedCtorClasses = {
      for (final key in _allPartsDead(
        candidates.where((candidate) => candidate.kind == .constructor),
        dead,
      ))
        // A dead class is removed whole (its constructors go with it), so its
        // constructors are never reported on their own — nothing to guard.
        if (!(deadClassNames[key.path]?.contains(key.name) ?? false) &&
            needsConstructor(classes[key]))
          key,
    };

    final enumValuesIterated = {
      for (final (i, candidate) in candidates.indexed)
        if (candidate.kind == .enum$ &&
            (candidate.outline.element.usesOwnValues ||
                refsByCandidate[i].any(syntax.isEnumValuesAccess)))
          candidate.key,
    };

    // Unnamed extensions on one type share a key; merging can only keep.
    final extensionsByKey = candidates
        .where((candidate) => candidate.isExtension)
        .groupListsBy((extension) => extension.key);
    final deadOutlines = {for (final candidate in dead) candidate.outline};
    final extensionsWithLiveMembers = {
      for (final MapEntry(:key, value: extensions) in extensionsByKey.entries)
        // A member that isn't a dead candidate counts as live, also one that
        // `--kinds` or `--no-public` leaves out. A local function in a member
        // is no member.
        if (!extensions.every(
          (extension) =>
              extension.outline.children.every(deadOutlines.contains),
        ))
          key,
    };

    return .new(
      emptiedEnums: emptiedEnums,
      blockedCtorClasses: blockedCtorClasses,
      enumValuesIterated: enumValuesIterated,
      extensionsWithLiveMembers: extensionsWithLiveMembers,
      deadExtensions: {
        for (final MapEntry(:key, value: extensions) in extensionsByKey.entries)
          if (!extensionsWithLiveMembers.contains(key) &&
              extensions.every(dead.contains))
            key,
      },
    );
  }

  /// Returns the keys of the declarations that contain [parts], such as enum
  /// values or constructors, and all of whose [parts] are in [dead].
  static List<DeclKey> _allPartsDead(
    Iterable<Candidate> parts,
    Set<Candidate> dead,
  ) => [
    for (final MapEntry(key: container, value: contained)
        in parts.groupListsBy((part) => part.containerKey).entries)
      if (contained.every(dead.contains)) ?container,
  ];

  final Set<DeclKey> emptiedEnums;
  final Set<DeclKey> blockedCtorClasses;
  final Set<DeclKey> enumValuesIterated;
  final Set<DeclKey> extensionsWithLiveMembers;
  final Set<DeclKey> deadExtensions;
}
