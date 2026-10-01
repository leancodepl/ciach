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
    return DeadSpans._(byPath);
  }

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

  /// The outermost finding whose removal deletes [position] in [path].
  UnusedDeclaration? ownerOf(String path, Position position) {
    final spans = _byPath[path];
    if (spans == null) {
      return null;
    }
    _Span? outermost;
    for (final span in spans) {
      if (_contains(span.range, position) &&
          (outermost == null || _isOutside(span.range, outermost.range))) {
        outermost = span;
      }
    }
    return outermost?.owner;
  }

  /// Every finding whose removal deletes [position] in [path], each once.
  Iterable<UnusedDeclaration> ownersOf(String path, Position position) => {
    for (final span in _byPath[path] ?? const <_Span>[])
      if (_contains(span.range, position)) span.owner,
  };

  /// Whether another finding's removal deletes [finding] too.
  bool enclosesInAnother(UnusedDeclaration finding, String rootPath) {
    final spans = _byPath[_absolute(finding.filePath, rootPath)];
    if (spans == null) {
      return false;
    }
    final start = _start(finding.fullRange);
    return spans.any(
      (span) => !identical(span.owner, finding) && _contains(span.range, start),
    );
  }

  /// Whether [other] deletes the same source.
  bool sameAs(DeadSpans other) => _sameSource.equals(_byPath, other._byPath);

  /// Compares spans by range alone: each round's findings are new objects, so
  /// their owners never match.
  static final _sameSource = MapEquality<String, Iterable<_Span>>(
    values: UnorderedIterableEquality(EqualityBy((span) => span.range)),
  );

  static bool _contains(DeclarationRange range, Position position) =>
      _start(range).atOrBefore(position) && position.atOrBefore(_end(range));

  /// Whether [a] is the outer of two spans that both contain a position: it
  /// starts earlier, or starts at the same place and ends later.
  static bool _isOutside(DeclarationRange a, DeclarationRange b) =>
      _start(a).isBefore(_start(b)) ||
      (_start(a) == _start(b) && _end(b).isBefore(_end(a)));

  static Position _start(DeclarationRange range) =>
      Position(line: range.startLine, character: range.startColumn);

  static Position _end(DeclarationRange range) =>
      Position(line: range.endLine, character: range.endColumn);

  static String _absolute(String filePath, String rootPath) =>
      p.normalize(p.joinAll([rootPath, ...p.posix.split(filePath)]));
}

typedef _Span = ({DeclarationRange range, UnusedDeclaration owner});
