import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, Range, SelectionRange;

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
    this._client,
    this._sources, {
    required Set<String> scannedPaths,
    required String rootPath,
  }) : _scannedPaths = scannedPaths,
       _rootPath = rootPath;

  final LspClient _client;

  /// Source text and the selection ranges fetched for the overrides below.
  final SourceIndex _sources;

  /// The files this run collected declarations from; nothing else is edited.
  final Set<String> _scannedPaths;

  final String _rootPath;

  /// The kinds an override is deleted as. A `field` needs two further checks
  /// — see [_fieldIsRemovable].
  static const _removableKinds = <OutlineKind>{
    .method,
    .getter,
    .setter,
    .field,
  };

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
    final found = _nodeNamedAt(outline, start);
    if (found == null || !_removableKinds.contains(found.node.element.kind)) {
      return null;
    }
    final node = found.node;
    if (node.element.kind == .field &&
        !await _fieldIsRemovable(uri, path, node, found.parent, start)) {
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

  /// Whether the field override [node] in [type] can be deleted on its own.
  ///
  /// Two shapes cannot. A declaring parameter of a primary constructor is a
  /// field too, and deleting one changes the constructor signature at every
  /// call site. A declarator sharing a statement with others
  /// (`final int a = 1, b = 2;`) covers only its own text, so deleting it
  /// would leave the statement malformed.
  Future<bool> _fieldIsRemovable(
    Uri uri,
    String path,
    Outline node,
    Outline? type,
    Position name,
  ) async {
    final List<SelectionRange?> ranges;
    try {
      ranges = await _client.selectionRanges(uri, [name]);
    } on Object {
      return false;
    }
    final innermost = ranges.single;
    if (innermost == null) {
      return false;
    }
    _sources.cacheSelectionRange(path, name, innermost);
    if (_sources.isNameInTypeHeader(path, name, type)) {
      return false;
    }
    // Only the first declarator of a statement carries its modifiers, so a
    // node starting at its own name is a later one.
    if (node.range.start == node.codeRange.start) {
      return false;
    }
    // The declarator's parent covers every declarator in the statement; it
    // ends where this one does only when this one is the last.
    SelectionRange? declarator = innermost;
    while (declarator != null && !_covers(declarator, node.codeRange)) {
      declarator = declarator.parent;
    }
    final statement = declarator?.parent;
    return statement != null && statement.range.end == declarator!.range.end;
  }

  static bool _covers(SelectionRange node, Range range) =>
      node.range.start.atOrBefore(range.start) &&
      range.end.atOrBefore(node.range.end);

  /// The outline node whose name starts at [position], with the node it is
  /// declared in.
  static ({Outline node, Outline? parent})? _nodeNamedAt(
    Outline root,
    Position position,
  ) {
    for (final parent in root.descendants) {
      for (final child in parent.children) {
        if (child.element.range?.start == position) {
          return (node: child, parent: parent);
        }
      }
    }
    return null;
  }
}
