import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

/// The overrides of a dead member: spans to delete with it, or `blocked` when
/// one of them has to stay.
typedef OverriddenMember = ({List<CoupledRemoval> removals, bool blocked});

/// Couples a dead member's overrides to its removal.
///
/// An override is dead with the member it implements: a call through any
/// subclass would have referenced that member. It is not a candidate, though
/// (see [FinderOptions.skipOverrides]), so removing the member alone leaves it
/// overriding nothing — `override_on_non_overriding_member`.
///
/// `textDocument/implementation` answers with every override of a member,
/// transitively and across files.
final class OverrideRemovals {
  OverrideRemovals(
    this._client, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) : _scannedPaths = scannedPaths,
       _rootPath = rootPath;

  final LspClient _client;

  /// The files this run collected declarations from; nothing else is edited.
  final Set<String> _scannedPaths;

  final String _rootPath;

  /// The kinds an override is deleted as. Not `field`: in the outline a
  /// declaring parameter of a primary constructor is a field too, and deleting
  /// one changes the constructor signature at every call site.
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
      // An override that has to stay blocks the member.
      if (removal == null) {
        return _blocked;
      }
      removals.add(removal);
    }
    return (removals: removals, blocked: false);
  }

  /// The span to delete for the override at [location], or `null` when it has
  /// to stay: an unscanned file, a declaration that cannot be read, a kind this
  /// tool won't delete, or a reference of its own.
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
    // The answer points at the override's name — an outline node's element
    // range.
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
    // The member is dead, so a reference here is a use this run cannot see.
    if (refs.isNotEmpty) {
      return null;
    }
    return (
      filePath: relativePosix(path, _rootPath),
      range: node.range.toDeclarationRange,
    );
  }
}
