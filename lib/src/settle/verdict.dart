import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/conventions/serialization.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/remove_safety.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/source/syntax_rules.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// What becomes of one unused candidate: silently suppressed, reported but
/// report-only, or a finding — and how that finding is spelled.
final class Verdict {
  Verdict({
    required this.options,
    required SourceIndex sources,
    required ReferenceClassifier classifier,
  }) : _sources = sources,
       _classifier = classifier;

  final FinderOptions options;
  final SourceIndex _sources;
  final ReferenceClassifier _classifier;

  /// Advisory note attached to a sole, zero-parameter private constructor
  /// (`Foo._();`) — the classic prevent-instantiation marker. Such a
  /// constructor is still reported (and removable) like any other dead code,
  /// but the note points at the idiomatic alternative.
  static const _preventInstantiationHint =
      'looks like a prevent-instantiation constructor — for a '
      'non-instantiable static-only class, prefer `abstract final class`';

  static const _primaryConstructorHint =
      'primary constructor — declared in the class header, so it cannot be removed without removing the class';

  static const _declaringParameterHint =
      'declaring parameter of the primary constructor — removing it changes '
      'the constructor signature at every call site';

  static const pairedStateHint =
      'its State class is used elsewhere, so it would be left extending State of a removed widget';

  /// The hint for a used enum whose values are all unused.
  static const emptiedEnumHint =
      'none of its values are used, and an enum needs at least one value';

  static const namedOnlyInClausesHint =
      'only `with` or `implements` clauses use it; `--remove` also removes it from them';

  static const overriddenHint =
      'overridden by a declaration --remove will not delete — that override would be left overriding nothing';

  /// The hint for a field or top-level variable whose cut the finder couldn't
  /// work out.
  static const noCutHint =
      "the analysis server didn't say where its statement ends, so `--remove` leaves it; remove it manually";

  /// The hint for a type with unused members that only doc comments mention.
  static const docOnlyTypeHint =
      'only doc comments mention it; remove those mentions and `--remove` deletes it';

  /// Whether an unused [candidate] should be silently suppressed (never
  /// reported): a live freezed-union arm, an exempt `toJson` hook, a
  /// constructor removed with its already-dead class, an extension or its
  /// members (see [RemoveSafety.deadExtensions]), or an enum value reached
  /// only through `.values` iteration.
  bool isSuppressed(
    Candidate candidate,
    int index,
    Set<int> freezedUnionArms,
    Map<String, Set<String>> deadClassNames,
    RemoveSafety safety,
  ) {
    if (freezedUnionArms.contains(index)) {
      return true;
    }
    if (!options.reportToJson && isToJsonHook(candidate)) {
      return true;
    }
    if (_isRemovedWithDeadClass(candidate, deadClassNames)) {
      return true;
    }
    // Used through its members, never by name.
    if (candidate.isExtension &&
        !safety.deadExtensions.contains(candidate.key)) {
      return true;
    }
    final containerKey = candidate.containerKey;
    if (containerKey == null) {
      return false;
    }
    if (candidate.isExtensionMember &&
        safety.deadExtensions.contains(containerKey)) {
      return true;
    }
    return candidate.isEnumValue &&
        safety.enumValuesIterated.contains(containerKey);
  }

  /// Whether a dead [candidate] is real but must *not* be auto-removed, because
  /// doing so would break the build:
  ///
  /// * a class kept dead only by type patterns under `--also union-members`
  ///   (never constructed, only matched): deleting a sealed member and its
  ///   scattered `case`s is a source rewrite this tool won't attempt;
  /// * an enum value whose removal would empty a still-referenced enum;
  /// * the last constructor of a live class with `final` fields or
  ///   super-constructor forwarding;
  /// * a primary constructor or one of its declaring parameters.
  ///
  /// Each is surfaced so a human can act on it, but the remover leaves it — and
  /// anything coupled to it — entirely alone.
  ///
  /// Without [groupGuards], the two guards that block a whole group (every
  /// value of an enum, every constructor of a class) are skipped.
  bool isRemovalBlocked(
    Candidate candidate,
    List<Location> refs,
    RemoveSafety safety, {
    bool groupGuards = true,
  }) {
    final containerKey = candidate.containerKey;
    return (candidate.symbol.kind == .class$ &&
            options.unusedUnionMembers &&
            _classifier.isPatternMatchedClass(candidate, refs)) ||
        (groupGuards &&
            candidate.isEnumValue &&
            containerKey != null &&
            safety.emptiedEnums.contains(containerKey)) ||
        (groupGuards &&
            candidate.symbol.kind == .constructor &&
            containerKey != null &&
            safety.blockedCtorClasses.contains(containerKey)) ||
        _isHeaderDeclaration(candidate) ||
        _translations(candidate) != null;
  }

  /// Whether [candidate] is a member a subclass could override. A declaring
  /// parameter is never removed anyway.
  bool canBeOverridden(Candidate candidate) => switch (candidate.symbol.kind) {
    .method || .property || .field =>
      candidate.container != null &&
          !candidate.isExtensionMember &&
          !_isHeaderDeclaration(candidate),
    _ => false,
  };

  String? hintFor(Candidate candidate) {
    if (_translations(candidate) case final t?) {
      return 'generated by gen-l10n; remove the message from ${t.arbFile} instead';
    }
    if (_isHeaderDeclaration(candidate)) {
      return candidate.symbol.kind == .constructor
          ? _primaryConstructorHint
          : _declaringParameterHint;
    }
    return candidate.isPreventInstantiationCtor
        ? _preventInstantiationHint
        : null;
  }

  UnusedDeclaration finding(
    Candidate candidate,
    String rootPath, {
    List<CoupledRemoval> coupledRemovals = const [],
    bool removalBlocked = false,
    String? hint,
    List<DeadReferrer> onlyReferencedFrom = const [],
  }) {
    final symbol = candidate.symbol;
    // An unnamed extension's selection range is its `on` type.
    final start = candidate.isUnnamedExtension
        ? symbol.range.start
        : symbol.selectionRange.start;
    final name = symbol.declarationName(candidate.container);
    // `extension on T` is no name to qualify members by.
    final container = candidate.isInUnnamedExtension
        ? null
        : candidate.container;
    return .new(
      name: name,
      kind: symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
        isMixin: candidate.isMixin,
      ),
      filePath: relativePosix(candidate.path, rootPath),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      // A member of a private type or of an unnamed extension is private too.
      isPrivate:
          isPrivateName(name) ||
          (container?.let(isPrivateName) ?? false) ||
          candidate.isInUnnamedExtension,
      container: container,
      isEnumValue: candidate.isEnumValue,
      range: symbol.declarationRange,
      fullRange: candidate.outline.range.toDeclarationRange,
      coupledRemovals: coupledRemovals,
      removalBlocked: removalBlocked,
      hint: hint,
      onlyReferencedFrom: onlyReferencedFrom,
    );
  }

  Translations? _translations(Candidate candidate) =>
      translationsOf(candidate, options.translations, options.rootPath);

  /// See [StructuralChecks.isDeclaredInTypeHeader].
  bool _isHeaderDeclaration(Candidate candidate) =>
      switch (candidate.symbol.kind) {
        .constructor || .field => _sources.isDeclaredInTypeHeader(candidate),
        _ => false,
      };

  /// Whether [candidate] goes with an already-dead class's own declaration —
  /// any constructor, or a declaring parameter — so a single removal is not
  /// reported twice.
  bool _isRemovedWithDeadClass(
    Candidate candidate,
    Map<String, Set<String>> deadClassNames,
  ) =>
      (candidate.symbol.kind == .constructor ||
          _isHeaderDeclaration(candidate)) &&
      (deadClassNames[candidate.path]?.contains(candidate.container) ?? false);
}
