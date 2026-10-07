import 'package:ciach/src/models.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// The source `--remove` would delete: each removable finding's
/// [UnusedDeclaration.fullRange] and its coupled removals. A reference inside
/// these spans keeps nothing alive.
///
/// A field declarator counts as deleted even in the rare statement the remover
/// can't parse and leaves in place.
final class DeadSpans {
  DeadSpans._(this._byPath);

  /// The spans of the findings `--remove` would delete, by absolute path.
  factory DeadSpans.of(Iterable<UnusedDeclaration> findings, String rootPath) {
    final byPath = <String, List<_Span>>{};
    for (final finding in findings) {
      if (finding.removalBlocked) {
        continue;
      }
      byPath.putIfAbsent(_absolute(finding.filePath, rootPath), () => []).add((
        range: finding.fullRange,
        owner: finding,
      ));
      for (final coupled in finding.coupledRemovals) {
        byPath.putIfAbsent(_absolute(coupled.filePath, rootPath), () => []).add(
          (range: coupled.fullRange, owner: finding),
        );
      }
    }
    return DeadSpans._({
      for (final MapEntry(key: path, value: spans) in byPath.entries)
        path: _FileSpans(spans),
    });
  }

  static final empty = DeadSpans._(const {});

  final Map<String, _FileSpans> _byPath;

  /// How many findings these spans delete.
  int get length => {
    for (final file in _byPath.values)
      for (final span in file.spans) span.owner,
  }.length;

  bool get isEmpty => _byPath.isEmpty;

  bool get isNotEmpty => _byPath.isNotEmpty;

  bool covers(String path, Position position) =>
      ownerOf(path, position) != null;

  /// The outermost finding whose removal deletes [position] in [path].
  UnusedDeclaration? ownerOf(String path, Position position) =>
      _byPath[path]?.containing(position).lastOrNull?.owner;

  /// Every finding whose removal deletes [position] in [path].
  Iterable<UnusedDeclaration> ownersOf(String path, Position position) => {
    for (final span in _byPath[path]?.containing(position) ?? const <_Span>[])
      span.owner,
  };

  /// Whether another finding's removal deletes [finding] too.
  bool enclosesInAnother(UnusedDeclaration finding, String rootPath) =>
      _byPath[_absolute(finding.filePath, rootPath)]
          ?.containing(_start(finding.fullRange))
          .any((span) => !identical(span.owner, finding)) ??
      false;

  /// Whether [other] deletes the same source.
  bool sameAs(DeadSpans other) => _sameSource.equals(_byPath, other._byPath);

  /// Compares spans by range alone: each round's findings are new objects, so
  /// their owners never match.
  static final _sameSource = MapEquality<String, _FileSpans>(
    values: EqualityBy<_FileSpans, Iterable<_Span>>(
      (file) => file.spans,
      UnorderedIterableEquality(
        EqualityBy<_Span, DeclarationRange>((span) => span.range),
      ),
    ),
  );

  static bool _contains(DeclarationRange range, Position position) =>
      _start(range).atOrBefore(position) && position.atOrBefore(_end(range));

  static Position _start(DeclarationRange range) =>
      Position(line: range.startLine, character: range.startColumn);

  static Position _end(DeclarationRange range) =>
      Position(line: range.endLine, character: range.endColumn);

  static String _absolute(String filePath, String rootPath) =>
      p.normalize(p.joinAll([rootPath, ...p.posix.split(filePath)]));
}

typedef _Span = ({DeclarationRange range, UnusedDeclaration owner});

/// One file's spans, sorted by start with the outer of two equal starts
/// first, each linked to the nearest span around it. Declarations nest, so
/// the spans containing a position are the chain of parents above the last
/// span starting before it, and a lookup walks that chain rather than every
/// span. A file whose spans overlap without nesting is searched linearly.
final class _FileSpans {
  factory _FileSpans(List<_Span> spans) {
    final sorted = [...spans];
    mergeSort(
      sorted,
      compare: (a, b) {
        final byStart = _compare(
          DeadSpans._start(a.range),
          DeadSpans._start(b.range),
        );
        return byStart != 0
            ? byStart
            : _compare(DeadSpans._end(b.range), DeadSpans._end(a.range));
      },
    );
    final parents = List.filled(sorted.length, -1);
    final open = <int>[];
    var nested = true;
    for (var i = 0; i < sorted.length; i++) {
      final start = DeadSpans._start(sorted[i].range);
      while (open.isNotEmpty &&
          DeadSpans._end(sorted[open.last].range).isBefore(start)) {
        open.removeLast();
      }
      if (open.isNotEmpty) {
        final end = DeadSpans._end(sorted[i].range);
        nested &= end.atOrBefore(DeadSpans._end(sorted[open.last].range));
        parents[i] = open.last;
      }
      open.add(i);
    }
    return _FileSpans._(sorted, parents, nested);
  }

  _FileSpans._(this.spans, this._parents, this._nested);

  final List<_Span> spans;
  final List<int> _parents;
  final bool _nested;

  /// The spans containing [position], innermost first.
  Iterable<_Span> containing(Position position) sync* {
    if (!_nested) {
      yield* spans.reversed.where(
        (span) => DeadSpans._contains(span.range, position),
      );
      return;
    }
    var i = _lastStartingBefore(position);
    while (i >= 0 && !DeadSpans._contains(spans[i].range, position)) {
      i = _parents[i];
    }
    for (; i >= 0; i = _parents[i]) {
      yield spans[i];
    }
  }

  /// The index of the last span that starts at or before [position], or -1.
  int _lastStartingBefore(Position position) {
    var low = 0;
    var high = spans.length;
    while (low < high) {
      final mid = (low + high) >> 1;
      if (DeadSpans._start(spans[mid].range).atOrBefore(position)) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }

  static int _compare(Position a, Position b) =>
      a == b ? 0 : (a.isBefore(b) ? -1 : 1);
}
