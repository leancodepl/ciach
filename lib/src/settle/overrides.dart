import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

/// The overrides of a dead member: spans to delete with it, or `blocked` when
/// one of them has to stay.
typedef OverriddenMember = ({List<CoupledRemoval> removals, bool blocked});

/// Couples a dead member's overrides to its removal.
///
/// An override is dead with the member it implements — a call through any
/// subclass would have referenced that member — but it is not a candidate
/// (see [FinderOptions.skipOverrides]), so removing the member alone would
/// leave it overriding nothing. [ResolvedFiles.overridesOf] lists every
/// override of a member, transitively and across files. Lookups are cached
/// by candidate index across the rounds of a run.
final class OverrideRemovals {
  OverrideRemovals(
    this._files, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) : _scannedPaths = scannedPaths,
       _rootPath = rootPath;

  final ResolvedFiles _files;

  /// The files this run collected declarations from; nothing else is edited.
  final Set<String> _scannedPaths;

  final String _rootPath;

  /// The `// ciach:` markers of each file an override lives in, by path.
  final _markers = <String, IgnoreMarkers>{};

  /// The kinds of the overrides that are deleted. A `field` goes as a
  /// declarator, so it can share a statement.
  static const _removableKinds = <OutlineKind>{
    .method,
    .getter,
    .setter,
    .field,
  };

  static const blocked = (removals: <CoupledRemoval>[], blocked: true);

  /// Override lookups by candidate index, cached across rounds.
  final _byMember = <int, OverriddenMember>{};

  /// The overrides to delete along with each of the dead [members], indexes
  /// into [candidates], by index. Members with nothing to say are left out.
  /// A member one of whose overrides is in [kept] is blocked instead: that
  /// override has to stay, so the member does too.
  Map<int, OverriddenMember> couple(
    List<Candidate> candidates,
    List<int> members, {
    required DeadSpans kept,
  }) {
    _lookUp(members.whereNot(_byMember.containsKey).toList(), candidates);
    final byCandidate = <int, OverriddenMember>{};
    var coupled = 0;
    var couplingMembers = 0;
    var blockedMembers = 0;
    for (final index in members) {
      var result = _byMember[index]!;
      if (result.removals.any((removal) => _isIn(kept, removal))) {
        result = blocked;
      }
      if (result.removals.isEmpty && !result.blocked) {
        continue;
      }
      byCandidate[index] = result;
      coupled += result.removals.length;
      if (result.removals.isNotEmpty) {
        couplingMembers++;
      }
      if (result.blocked) {
        blockedMembers++;
      }
    }
    if (coupled > 0) {
      _log.fine(
        'Coupling ${plural(coupled, 'override', 'overrides')} to '
        '${plural(couplingMembers, 'dead member', 'dead members')}.',
      );
    }
    if (blockedMembers > 0) {
      _log.fine(
        '${plural(blockedMembers, 'dead member', 'dead members')} ${pluralWord(blockedMembers, 'is', 'are')} '
        'overridden where --remove cannot follow; left in place.',
      );
    }
    return byCandidate;
  }

  /// Looks up and caches the overrides of the [unchecked] members.
  void _lookUp(List<int> unchecked, List<Candidate> candidates) {
    if (unchecked.isEmpty) {
      return;
    }
    _log.info(
      'Checking ${plural(unchecked.length, 'dead member', 'dead members')} for overrides…',
    );
    for (final index in unchecked) {
      _byMember[index] = of(candidates[index]);
    }
  }

  /// Whether [spans] cover the start of [removal].
  bool _isIn(DeadSpans spans, CoupledRemoval removal) => spans.covers(
    absoluteUnder(removal.filePath, _rootPath),
    .new(line: removal.range.startLine, character: removal.range.startColumn),
  );

  /// The overrides of the dead [member], as spans to remove with it.
  OverriddenMember of(Candidate member) {
    final removals = _files
        .overridesOf(member.path, member.outline.nameRange.start)
        .map(_removalFor)
        .toList();
    // An override that has to stay blocks the member.
    return removals.contains(null)
        ? blocked
        : (removals: removals.nonNulls.toList(), blocked: false);
  }

  /// The span to delete for the override at [location], or `null` when it has
  /// to stay: an unscanned file, a declaration that cannot be read, a kind
  /// this tool won't delete, or one a `// ciach:` marker keeps.
  CoupledRemoval? _removalFor(Location location) {
    final path = location.path;
    if (!_scannedPaths.contains(path)) {
      return null;
    }
    final file = _files.resolved(path);
    // [ResolvedFiles.overridesOf] gives where the override's name starts,
    // which is where an outline node's element range starts.
    final start = location.range.start;
    final found = file?.outline.let((outline) => _nodeNamedAt(outline, start));
    if (file == null ||
        found == null ||
        !_removableKinds.contains(found.node.element.kind)) {
      return null;
    }
    final node = found.node;
    if ((_markers[path] ??= .parse(
          file.content,
        )).keeping(start: node.range.start.line, nameLine: start.line) !=
        null) {
      return null;
    }
    // Deleting a declaring parameter changes the constructor signature at
    // every call site.
    if (node.element.isInTypeHeader) {
      return null;
    }
    // No reference to check: a member's references are those of its whole
    // family of overrides, so the member being dead means none of them is
    // referenced either.
    return (
      filePath: relativePosix(path, _rootPath),
      kind: node.element.reportedKind!,
      isClauseEntry: false,
      range: node.codeRange.toDeclarationRange,
      fullRange: node.range.toDeclarationRange,
      cut: null,
    );
  }

  /// The outline node whose name starts at [position], with the node it is
  /// declared in. A name is inside every range around it, so this descends.
  static ({Outline node, Outline? parent})? _nodeNamedAt(
    Outline root,
    Position position,
  ) {
    var parent = root;
    while (true) {
      final child = parent.childAt(position);
      if (child == null) {
        return null;
      }
      if (child.element.range?.start == position) {
        return (node: child, parent: parent);
      }
      parent = child;
    }
  }
}
