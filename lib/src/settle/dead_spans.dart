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

  bool get isEmpty => _byPath.isEmpty;

  bool get isNotEmpty => _byPath.isNotEmpty;

  bool covers(String path, Position position) =>
      ownerOf(path, position) != null;

  /// The outermost finding whose removal deletes [position] in [path]. The
  /// name of a type at the start of its own clause entry, like `C` in
  /// `class A with C<T> {}`, has no owner.
  UnusedDeclaration? ownerOf(String path, Position position) => maxBy(
    [
      if (_byPath[path] case final spans?)
        for (final span in spans)
          // `--remove` deletes `C` with its entry, but if the name didn't
          // count as a reference, `C` would be reported as unused, and
          // `--remove` would leave the entry.
          if (_contains(span.range, position) &&
              !(span.isClauseEntry && position == _start(span.range)))
            span,
    ],
    (span) => span.range,
    compare: _compareByNesting,
  )?.owner;

  /// Every finding whose removal deletes [position] in [path]. Unlike
  /// [ownerOf], this includes the type whose clause entry starts at
  /// [position].
  Iterable<UnusedDeclaration> ownersOf(String path, Position position) => {
    if (_byPath[path] case final spans?)
      for (final span in spans)
        if (_contains(span.range, position)) span.owner,
  };

  /// The findings whose removal deletes one of [refs], in source order. A
  /// declaration with no other references is dead only because they are.
  List<DeadReferrer> referrersAmong(Iterable<Location> refs) {
    if (isEmpty) {
      return const [];
    }
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
            _contains(span.range, _start(finding.fullRange)),
      ) ??
      false;

  /// Whether [other] deletes the same source.
  bool sameAs(DeadSpans other) => _sameSource.equals(_byPath, other._byPath);

  /// Compares spans by range alone: each round's findings are new objects, so
  /// their owners never match.
  static final _sameSource = MapEquality<String, Iterable<_Span>>(
    values: UnorderedIterableEquality(EqualityBy((span) => span.range)),
  );

  static bool _contains(DeclarationRange range, Position position) =>
      _start(range).atOrBefore(position) && position.atOrBefore(_end(range));

  /// Orders two spans that both contain a position from the inner to the
  /// outer: the outer one starts earlier, or starts at the same place and ends
  /// later.
  static int _compareByNesting(DeclarationRange a, DeclarationRange b) =>
      switch (_start(b).compareTo(_start(a))) {
        0 => _end(a).compareTo(_end(b)),
        final byStart => byStart,
      };

  static Position _start(DeclarationRange range) =>
      .new(line: range.startLine, character: range.startColumn);

  static Position _end(DeclarationRange range) =>
      .new(line: range.endLine, character: range.endColumn);
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
