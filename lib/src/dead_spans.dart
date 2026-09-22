import 'package:ciach/src/models.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// The text a removal deletes: every removable finding's [UnusedDeclaration.fullRange]
/// and the spans coupled to it. A reference inside keeps nothing alive.
///
/// A declarator the remover declines to trim out of its statement counts as
/// gone here too; only a statement it can't parse exposes that.
final class DeadSpans {
  DeadSpans._(this._byPath, this.length);

  /// The spans of the findings `--remove` would delete, by absolute path.
  factory DeadSpans.of(Iterable<UnusedDeclaration> findings, String rootPath) {
    final byPath = <String, List<_Span>>{};
    var length = 0;
    for (final finding in findings) {
      if (finding.removalBlocked) {
        continue;
      }
      length++;
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
    return DeadSpans._(byPath, length);
  }

  static final empty = DeadSpans._(const {}, 0);

  final Map<String, List<_Span>> _byPath;

  /// Findings that contributed.
  final int length;

  bool get isEmpty => length == 0;

  bool get isNotEmpty => length > 0;

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
          (outermost == null || _startsBefore(span.range, outermost.range))) {
        outermost = span;
      }
    }
    return outermost?.owner;
  }

  /// Whether another finding's removal deletes [finding] too.
  bool enclosesInAnother(UnusedDeclaration finding, String rootPath) {
    final spans = _byPath[_absolute(finding.filePath, rootPath)];
    if (spans == null) {
      return false;
    }
    final start = Position(
      line: finding.fullRange.startLine,
      character: finding.fullRange.startColumn,
    );
    return spans.any(
      (span) => !identical(span.owner, finding) && _contains(span.range, start),
    );
  }

  bool sameAs(DeadSpans other) {
    if (length != other.length || _byPath.length != other._byPath.length) {
      return false;
    }
    for (final MapEntry(key: path, value: spans) in _byPath.entries) {
      final theirs = other._byPath[path];
      if (theirs == null ||
          !const SetEquality<DeclarationRange>().equals(
            {for (final span in spans) span.range},
            {for (final span in theirs) span.range},
          )) {
        return false;
      }
    }
    return true;
  }

  static bool _contains(DeclarationRange range, Position position) {
    final start = Position(line: range.startLine, character: range.startColumn);
    final end = Position(line: range.endLine, character: range.endColumn);
    return start.atOrBefore(position) && position.atOrBefore(end);
  }

  static bool _startsBefore(DeclarationRange a, DeclarationRange b) =>
      a.startLine < b.startLine ||
      (a.startLine == b.startLine && a.startColumn < b.startColumn);

  static String _absolute(String filePath, String rootPath) =>
      p.normalize(p.joinAll([rootPath, ...p.posix.split(filePath)]));
}

typedef _Span = ({DeclarationRange range, UnusedDeclaration owner});
