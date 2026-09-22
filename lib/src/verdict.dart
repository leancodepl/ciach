import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/conventions/serialization.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
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
      'primary constructor — declared in the class header, so it cannot be '
      'removed without removing the class';

  static const _declaringParameterHint =
      'declaring parameter of the primary constructor — removing it changes '
      'the constructor signature at every call site';

  static const overriddenHint =
      'overridden by a declaration --remove will not delete — that override '
      'would be left overriding nothing';

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
  /// * a class kept dead only by type patterns under `--unused-union-members`
  ///   (never constructed, only matched): deleting a sealed member and its
  ///   scattered `case`s is a source rewrite this tool won't attempt;
  /// * an enum value whose removal would empty a still-referenced enum;
  /// * the last constructor of a live class with `final` fields or
  ///   super-constructor forwarding;
  /// * a primary constructor or one of its declaring parameters.
  ///
  /// Each is surfaced so a human can act on it, but the remover leaves it — and
  /// anything coupled to it — entirely alone.
  bool isRemovalBlocked(
    Candidate candidate,
    List<Location> refs,
    RemoveSafety safety,
  ) {
    final containerKey = candidate.containerKey;
    return (candidate.symbol.kind == .class$ &&
            options.unusedUnionMembers &&
            _classifier.isPatternMatchedClass(candidate, refs)) ||
        (candidate.isEnumValue &&
            containerKey != null &&
            safety.emptiedEnums.contains(containerKey)) ||
        (candidate.symbol.kind == .constructor &&
            containerKey != null &&
            safety.blockedCtorClasses.contains(containerKey)) ||
        _isHeaderDeclaration(candidate);
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
  }) {
    final symbol = candidate.symbol;
    // An unnamed extension's selection range is its `on` type.
    final start = candidate.isUnnamedExtension
        ? symbol.range.start
        : symbol.selectionRange.start;
    final name = symbol.declarationName(candidate.container);
    // `extension on T` is no name to qualify members by.
    final container = _isInUnnamedExtension(candidate)
        ? null
        : candidate.container;
    return .new(
      name: name,
      kind: symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
      ),
      filePath: relativePosix(candidate.path, rootPath),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      isPrivate: isPrivateName(name),
      container: container,
      isEnumValue: candidate.isEnumValue,
      range: symbol.declarationRange,
      fullRange: candidate.outline.range.toDeclarationRange,
      coupledRemovals: coupledRemovals,
      removalBlocked: removalBlocked,
      hint: hint,
    );
  }

  /// See [StructuralChecks.isDeclaredInTypeHeader].
  bool _isHeaderDeclaration(Candidate candidate) =>
      switch (candidate.symbol.kind) {
        .constructor || .field => _sources.isDeclaredInTypeHeader(candidate),
        _ => false,
      };

  bool _isInUnnamedExtension(Candidate candidate) =>
      candidate.containerOutline?.element.isUnnamedExtension ?? false;

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

/// File, then line, then column.
int compareByLocation(UnusedDeclaration a, UnusedDeclaration b) {
  final byFile = a.filePath.compareTo(b.filePath);
  if (byFile != 0) {
    return byFile;
  }
  final byLine = a.line.compareTo(b.line);
  return byLine != 0 ? byLine : a.column.compareTo(b.column);
}
