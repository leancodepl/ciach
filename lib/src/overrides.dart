import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, SelectionRange, SymbolKind;

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

  /// The kinds an override is deleted as, and the kind the remover reads for
  /// each. A `field` is deleted as a declarator, so one sharing a statement
  /// with others (`final int a = 1, b = 2;`) is taken out of it, and the whole
  /// statement goes only when every declarator does.
  static const _removableKinds = <OutlineKind, SymbolKind>{
    .method: .method,
    .getter: .property,
    .setter: .property,
    .field: .field,
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
    final kind = _removableKinds[found?.node.element.kind];
    if (found == null || kind == null) {
      return null;
    }
    final node = found.node;
    // A declaring parameter of a primary constructor is a field too, and
    // deleting one changes the constructor signature at every call site.
    if (kind == .field &&
        await _isDeclaringParameter(uri, path, found.parent, start)) {
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
      kind: kind,
      range: node.codeRange.toDeclarationRange,
      fullRange: node.range.toDeclarationRange,
    );
  }

  /// Whether the field named at [name] is declared in [type]'s header — a
  /// declaring parameter of a primary constructor. `true` when the shape
  /// cannot be read, which keeps the declaration.
  Future<bool> _isDeclaringParameter(
    Uri uri,
    String path,
    Outline? type,
    Position name,
  ) async {
    final List<SelectionRange?> ranges;
    try {
      ranges = await _client.selectionRanges(uri, [name]);
    } on Object {
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
  /// declared in. Descends one level at a time, since a node's name is inside
  /// its own range and inside every range around it.
  static ({Outline node, Outline? parent})? _nodeNamedAt(
    Outline root,
    Position position,
  ) {
    var parent = root;
    while (true) {
      final child = _childAt(parent, position);
      if (child == null) {
        return null;
      }
      if (child.element.range?.start == position) {
        return (node: child, parent: parent);
      }
      parent = child;
    }
  }

  /// The child of [parent] covering [position]: the last one starting at or
  /// before it, if it reaches that far.
  static Outline? _childAt(Outline parent, Position position) {
    final child = lastStartingAtOrBefore(
      parent.children,
      position,
      (child) => child.range.start,
    );
    return child != null && position.atOrBefore(child.range.end) ? child : null;
  }
}
