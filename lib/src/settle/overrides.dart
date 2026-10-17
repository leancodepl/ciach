import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/dead_spans.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/source/syntax_rules.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, SelectionRange, SymbolKind;

final _log = Logger('ciach.finder');

/// The overrides of a dead member: spans to delete with it, or `blocked` when
/// one of them has to stay.
typedef OverriddenMember = ({List<CoupledRemoval> removals, bool blocked});

/// Couples a dead member's overrides to its removal.
///
/// An override is dead with the member it implements — a call through any
/// subclass would have referenced that member — but it is not a candidate
/// (see [FinderOptions.skipOverrides]), so removing the member alone would
/// leave it overriding nothing. `textDocument/implementation` answers with
/// every override of a member, transitively and across files. Lookups are
/// cached by candidate index across the rounds of a run.
final class OverrideRemovals {
  OverrideRemovals(
    this._client,
    this._sources, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) : _scannedPaths = scannedPaths,
       _rootPath = rootPath;

  final LspClient _client;

  final SourceIndex _sources;

  /// The files this run collected declarations from; nothing else is edited.
  final Set<String> _scannedPaths;

  final String _rootPath;

  /// The `// ciach:` markers of each file an override lives in.
  late final _markers = CachedMap<String, IgnoreMarkers>(
    (path) => .parse(_sources.content(path)),
  );

  static const _unlistedOverrides =
      'Could not find overrides; reported, not removed.';

  static const _uncheckedOverride =
      'Could not check an override; reported, not removed.';

  /// The kinds an override is deleted as, mapped to the kind the remover
  /// reads. A `field` goes as a declarator, so it can share a statement.
  static const _removableKinds = <OutlineKind, SymbolKind>{
    .method: .method,
    .getter: .property,
    .setter: .property,
    .field: .field,
  };

  static const _none = (removals: <CoupledRemoval>[], blocked: false);
  static const blocked = (removals: <CoupledRemoval>[], blocked: true);

  /// Override lookups by candidate index, cached across rounds.
  final _byMember = <int, OverriddenMember>{};

  /// The overrides to delete along with each of the dead [members], indexes
  /// into [candidates], by index. Members with nothing to say are left out.
  /// A member one of whose overrides is in [kept] is blocked instead: that
  /// override has to stay, so the member does too.
  Future<Map<int, OverriddenMember>> couple(
    List<Candidate> candidates,
    List<int> members, {
    required DeadSpans kept,
    required int concurrency,
  }) async {
    await _lookUp(
      members.whereNot(_byMember.containsKey).toList(),
      candidates,
      concurrency,
    );
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
  Future<void> _lookUp(
    List<int> unchecked,
    List<Candidate> candidates,
    int concurrency,
  ) async {
    if (unchecked.isEmpty) {
      return;
    }
    _log.info(
      'Checking ${plural(unchecked.length, 'dead member', 'dead members')} for overrides…',
    );
    final results = await mapPooled(
      unchecked,
      concurrency,
      (index) => of(candidates[index]),
    );
    for (final (i, index) in unchecked.indexed) {
      _byMember[index] = results[i];
    }
  }

  /// Whether [spans] cover the start of [removal].
  bool _isIn(DeadSpans spans, CoupledRemoval removal) => spans.covers(
    absoluteUnder(removal.filePath, _rootPath),
    .new(line: removal.range.startLine, character: removal.range.startColumn),
  );

  /// The overrides of the dead [member], as spans to remove with it.
  Future<OverriddenMember> of(Candidate member) async {
    final List<Location> overrides;
    try {
      overrides = await _client.implementations(
        member.uri,
        member.symbol.selectionRange.start,
      );
    } on LspRequestException catch (e) {
      recordProblem(
        _unlistedOverrides,
        e,
        path: member.path,
        position: member.symbol.selectionRange.start,
        name: [?member.container, member.symbol.name].join('.'),
      );
      return blocked;
    }
    if (overrides.isEmpty) {
      return _none;
    }
    final removals = <CoupledRemoval>[];
    for (final override in overrides) {
      // An override that has to stay blocks the member.
      final removal = await _removalFor(override);
      if (removal == null) {
        return blocked;
      }
      removals.add(removal);
    }
    return (removals: removals, blocked: false);
  }

  /// The span to delete for the override at [location], or `null` when it has
  /// to stay: an unscanned file, a declaration that cannot be read, a kind
  /// this tool won't delete, or one a `// ciach:` marker keeps.
  Future<CoupledRemoval?> _removalFor(Location location) async {
    final path = SourceIndex.pathOf(location.uri);
    if (!_scannedPaths.contains(path)) {
      return null;
    }
    final uri = Uri.parse(location.uri);
    // Every scanned file's outline was awaited while collecting candidates, so
    // this is a cache hit and can't time out.
    final outline = await _client.outline(uri);
    // The answer points at the override's name: an outline node's element range.
    final start = location.range.start;
    final found = _nodeNamedAt(outline, start);
    final kind = _removableKinds[found?.node.element.kind];
    if (found == null || kind == null) {
      return null;
    }
    final node = found.node;
    if (_markers[path].keeping(
          start: node.range.start.line,
          nameLine: start.line,
        ) !=
        null) {
      return null;
    }
    // Deleting a declaring parameter changes the constructor signature at
    // every call site.
    if (kind == .field &&
        await _isDeclaringParameter(uri, path, found.parent, start)) {
      return null;
    }
    // No reference to check: the server answers a member's references for
    // its whole family of overrides, so the member being dead means none of
    // them is referenced either.
    return (
      filePath: relativePosix(path, _rootPath),
      kind: kind,
      range: node.codeRange.toDeclarationRange,
      fullRange: node.range.toDeclarationRange,
      cut: null,
    );
  }

  /// Whether the field named at [name] is a declaring parameter of [type]'s
  /// primary constructor. `true` when the shape cannot be read.
  Future<bool> _isDeclaringParameter(
    Uri uri,
    String path,
    Outline? type,
    Position name,
  ) async {
    final List<SelectionRange?> ranges;
    try {
      ranges = await _client.selectionRanges(uri, [name]);
    } on LspRequestException catch (e) {
      recordProblem(_uncheckedOverride, e, path: path, position: name);
      return true;
    }
    final innermost = ranges.single;
    if (innermost == null) {
      return true;
    }
    _sources.cacheSelectionRange(path, name, innermost);
    return _sources.isNameInTypeHeader(path, name, type);
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
