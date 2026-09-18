import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// What to do about the overrides of a dead member: the spans to delete along
/// with it, or `blocked` when at least one of them cannot be deleted.
typedef OverriddenMember = ({List<CoupledRemoval> removals, bool blocked});

/// Couples a dead member's overrides to its removal.
///
/// A member with no references is dead even where subclasses override it: a
/// call through any of them would have referenced it, since the analyzer
/// resolves `dog.name` back to the `Animal.name` it implements. The whole
/// family is dead, but an `@override` member is not a candidate (see
/// [FinderOptions.skipOverrides]), so removing only the member the finder
/// reports leaves its overrides overriding nothing —
/// `override_on_non_overriding_member`.
///
/// The overrides come from `textDocument/implementation`, which answers with
/// every member overriding the one asked about, transitively and across files.
final class OverrideRemovals {
  OverrideRemovals(
    this._client, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) : _scannedPaths = scannedPaths,
       _rootPath = rootPath;

  final LspClient _client;

  /// The files this run collected declarations from — the only ones a coupled
  /// removal may touch.
  final Set<String> _scannedPaths;

  final String _rootPath;

  /// The kinds an override is deleted as: a member of the type's body, which
  /// goes as a whole node. A `field` is left alone — it can be a declaring
  /// parameter of a primary constructor, or initialized by a constructor that
  /// would no longer compile without it.
  static const _removableKinds = <OutlineKind>{.method, .getter, .setter};

  static const _none = (removals: <CoupledRemoval>[], blocked: false);
  static const _blocked = (removals: <CoupledRemoval>[], blocked: true);

  /// The overrides of the dead [member], as spans to remove with it.
  Future<OverriddenMember> of(Candidate member) async {
    final List<Location> overrides;
    try {
      overrides = await _client.implementations(
        member.uri,
        member.symbol.selectionRange.start,
      );
    } on Object {
      return _blocked;
    }
    if (overrides.isEmpty) {
      return _none;
    }
    final removals = <CoupledRemoval>[];
    for (final override in overrides) {
      final removal = await _removalFor(override);
      // One override that has to stay blocks the member: removing it would
      // leave that override overriding nothing.
      if (removal == null) {
        return _blocked;
      }
      removals.add(removal);
    }
    return (removals: removals, blocked: false);
  }

  /// The span to delete for the override at [location], or `null` when it has
  /// to stay: it is in a file this run did not scan, its declaration cannot be
  /// read, it is a kind this tool won't delete, or something references it.
  Future<CoupledRemoval?> _removalFor(Location location) async {
    final path = SourceIndex.pathOf(location.uri);
    if (!_scannedPaths.contains(path)) {
      return null;
    }
    final uri = Uri.parse(location.uri);
    final Outline outline;
    try {
      outline = await _client.outline(uri);
    } on Object {
      return null;
    }
    // `textDocument/implementation` answers with each override's name, which
    // is an outline node's `element.range`.
    final start = location.range.start;
    final node = outline.descendants.firstWhereOrNull(
      (node) => node.element.range?.start == start,
    );
    if (node == null || !_removableKinds.contains(node.element.kind)) {
      return null;
    }
    final List<Location> refs;
    try {
      refs = await _client.references(uri, start);
    } on Object {
      return null;
    }
    // The dead member has no references, so neither should its overrides; a
    // reference here means the analyzer sees a use this run does not.
    if (refs.isNotEmpty) {
      return null;
    }
    return (
      filePath: relativePosix(path, _rootPath),
      range: node.range.toDeclarationRange,
    );
  }
}
