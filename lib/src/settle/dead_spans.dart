import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';

/// The source `--remove` would delete: each removable finding's
/// [UnusedDeclaration.fullRange] and its coupled removals. A reference inside
/// these spans keeps nothing alive, except the name of a type at the start of
/// its own entry in a `with` or `implements` clause.
final class DeadSpans {
  DeadSpans._(this._byPath);

  /// The spans of the findings `--remove` would delete, by absolute path.
  factory DeadSpans.of(Iterable<UnusedDeclaration> findings, String rootPath) =>
      ._(
        [
          for (final finding in findings)
            if (!finding.removalBlocked) ...[
              (
                path: absoluteUnder(finding.filePath, rootPath),
                range: finding.fullRange,
                owner: finding,
                isClauseEntry: false,
              ),
              for (final coupled in finding.coupledRemovals)
                (
                  path: absoluteUnder(coupled.filePath, rootPath),
                  range: coupled.fullRange,
                  owner: finding,
                  isClauseEntry: coupled.isClauseEntry,
                ),
            ],
        ].groupListsBy((span) => span.path),
      );

  static final empty = DeadSpans._(const {});

  final Map<String, List<_Span>> _byPath;

  /// How many findings these spans delete.
  int get length => {
    for (final spans in _byPath.values)
      for (final span in spans) span.owner,
  }.length;

  bool covers(String path, int offset) => ownerOf(path, offset) != null;

  /// The outermost finding whose removal deletes [offset] in [path]. The
  /// name of a type at the start of its own clause entry, like `C` in
  /// `class A with C<T> {}`, has no owner.
  UnusedDeclaration? ownerOf(String path, int offset) => maxBy(
    [
      if (_byPath[path] case final spans?)
        for (final span in spans)
          // `--remove` deletes `C` with its entry, but if the name didn't
          // count as a reference, `C` would be reported as unused, and
          // `--remove` would leave the entry.
          if (_contains(span.range, offset) &&
              !(span.isClauseEntry && offset == span.range.start))
            span,
    ],
    (span) => span.range,
    compare: _compareByNesting,
  )?.owner;

  /// Every finding whose removal deletes [offset] in [path]. Unlike
  /// [ownerOf], this includes the type whose clause entry starts at [offset].
  Iterable<UnusedDeclaration> ownersOf(String path, int offset) => {
    if (_byPath[path] case final spans?)
      for (final span in spans)
        if (_contains(span.range, offset)) span.owner,
  };

  /// The findings whose removal deletes one of [refs], in source order. A
  /// declaration with no other references is dead only because they are.
  List<DeadReferrer> referrersAmong(Iterable<Location> refs) {
    final owners = {
      for (final loc in refs) ?ownerOf(loc.path, loc.range.start),
    };
    return [
      for (final owner in owners.sorted(compareByLocation))
        (
          qualifiedName: owner.qualifiedName,
          filePath: owner.filePath,
          line: owner.line,
        ),
    ];
  }

  /// Whether another finding's removal deletes [finding] too.
  bool enclosesInAnother(UnusedDeclaration finding, String rootPath) =>
      _byPath[absoluteUnder(finding.filePath, rootPath)]?.any(
        (span) =>
            !identical(span.owner, finding) &&
            _contains(span.range, finding.fullRange.start),
      ) ??
      false;

  /// Whether [other] deletes the same source.
  bool sameAs(DeadSpans other) => _sameSource.equals(_byPath, other._byPath);

  /// Compares spans by range alone: each round's findings are new objects, so
  /// their owners never match.
  static final _sameSource = MapEquality<String, Iterable<_Span>>(
    values: UnorderedIterableEquality(EqualityBy((span) => span.range)),
  );

  static bool _contains(DeclarationRange range, int offset) =>
      range.start <= offset && offset <= range.end;

  /// Orders two spans that both contain an offset from the inner to the
  /// outer: the outer one starts earlier, or starts at the same place and ends
  /// later.
  static int _compareByNesting(DeclarationRange a, DeclarationRange b) =>
      switch (b.start.compareTo(a.start)) {
        0 => a.end.compareTo(b.end),
        final byStart => byStart,
      };
}

/// `path` is the absolute path of the file that the span is in, and
/// `isClauseEntry` is true for the span of a type's entry in a `with` or
/// `implements` clause, which starts with the type's name.
typedef _Span = ({
  String path,
  DeclarationRange range,
  UnusedDeclaration owner,
  bool isClauseEntry,
});
