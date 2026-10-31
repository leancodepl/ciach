/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves the classes that the entry-point rules read: the supertypes of
/// each class. A rule can then match a subtype of the class that it names.
library;

import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Position, TypeHierarchyItem;

const _unresolvedClass =
    'Could not resolve the supertypes of this class; its members may be reported.';

/// A class with all its supertypes.
typedef _Hierarchy = ({ResolvedClass type, Set<ResolvedClass> supertypes});

/// The supertypes of the classes in the scanned files, resolved only in the
/// files that an entry-point rule which reads them applies to.
final class ResolvedClasses {
  ResolvedClasses(this._entryPoints);

  final EntryPoints _entryPoints;
  final _packages = PackageResolver();

  /// The supertypes of each class, by the file and the position of the
  /// class's name.
  final _byClassName = <(String, Position), Set<ResolvedClass>>{};

  /// A class and all its supertypes, by the file and the position of the
  /// class's name in its declaration.
  final _byClass = <(String, Position), Future<Set<ResolvedClass>>>{};

  /// Resolves the classes among [symbols], the document symbols of the open
  /// file [path] at [relativePath], so that [supertypesOf] can return them.
  Future<void> resolve(
    LspClient client,
    String path,
    String relativePath,
    List<DocumentSymbol> symbols,
  ) async {
    final lookups = _entryPoints.lookupsIn(relativePath);
    if (lookups.isEmpty) {
      return;
    }
    final config = _packages.configOf(p.dirname(path));
    await Future.wait([
      if (lookups.contains(ServerLookup.supertypes))
        for (final symbol in symbols.where((s) => s.kind == .class$))
          _resolveClass(client, config, path, symbol),
    ]);
  }

  /// Returns all the supertypes of the class [symbol] in [path].
  Set<ResolvedClass> supertypesOf(String path, DocumentSymbol symbol) =>
      _byClassName[(path, symbol.selectionRange.start)] ?? const {};

  /// Records the supertypes of the class [symbol].
  Future<void> _resolveClass(
    LspClient client,
    PackageConfig? config,
    String path,
    DocumentSymbol symbol,
  ) async {
    final name = symbol.selectionRange.start;
    try {
      final items = await client.typeHierarchyItems(File(path).uri, name);
      final hierarchies = await Future.wait([
        for (final item in items) _hierarchyOf(client, config, item),
      ]);
      _byClassName[(path, name)] = {
        for (final (:supertypes, type: _) in hierarchies) ...supertypes,
      };
    } on LspRequestException catch (e) {
      recordProblem(_unresolvedClass, e, path: path, position: name);
    }
  }

  /// Returns the class of [item] with all its supertypes. Their packages are
  /// those that [config] gives the files that declare them.
  Future<_Hierarchy> _hierarchyOf(
    LspClient client,
    PackageConfig? config,
    TypeHierarchyItem item,
  ) async {
    final type = _classOf(config, item);
    final all = await _withSupertypes(client, config, item);
    return (type: type, supertypes: {...all}..remove(type));
  }

  /// Returns the class of [item] and all its supertypes.
  Future<Set<ResolvedClass>> _withSupertypes(
    LspClient client,
    PackageConfig? config,
    TypeHierarchyItem item,
  ) => _byClass[(item.uri, item.selectionRange.start)] ??= () async {
    final supertypes = await client.supertypes(item);
    final classes = await Future.wait([
      for (final supertype in supertypes)
        _withSupertypes(client, config, supertype),
    ]);
    return {_classOf(config, item), for (final set in classes) ...set};
  }();

  /// Returns the class that [item] names. The server names a generic class
  /// `Story<T>`.
  static ResolvedClass _classOf(
    PackageConfig? config,
    TypeHierarchyItem item,
  ) => .new(
    item.name.withoutTypeArguments,
    config?.packageOf(.parse(item.uri))?.name,
  );
}
