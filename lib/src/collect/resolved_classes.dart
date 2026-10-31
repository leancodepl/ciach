/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves the classes that the entry-point rules read: the class of each
/// annotation that creates an object, such as `@DarkPreview()` or `@preview`,
/// and the supertypes of each class. A rule can then match a subtype of the
/// class that it names.
library;

import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/declared_values.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

const _unresolvedClass =
    'Could not resolve the supertypes of this class; its members may be reported.';

/// A class with all its supertypes.
typedef _Hierarchy = ({ResolvedClass type, Set<ResolvedClass> supertypes});

/// The classes of the annotations and the supertypes of the classes in the
/// scanned files, resolved only as far as the entry-point rules that apply to
/// each file read them.
final class ResolvedClasses {
  ResolvedClasses(this._sources, this._entryPoints);

  final SourceIndex _sources;
  final EntryPoints _entryPoints;
  final _packages = PackageResolver();

  /// The annotations, by the file and the position of the name that the
  /// annotation's `@` is followed by: `Preview` in `@Preview()`, `preview`
  /// in `@preview`.
  final _byAnnotation = <(String, Position), List<ResolvedAnnotation>>{};

  /// The supertypes of each class, by the file and the position of the
  /// class's name.
  final _byClassName = <(String, Position), Set<ResolvedClass>>{};

  /// The classes that a definition declares, by its file and position. The
  /// same annotation in many places has the same definition.
  final _byDefinition = <(String, Position), Future<List<_Hierarchy>>>{};

  /// The classes of the objects that a constant holds, by the position of
  /// its definition.
  final _byConstant = <(String, Position), Future<List<_Hierarchy>>>{};

  /// A class and all its supertypes, by the file and the position of the
  /// class's name in its declaration.
  final _byClass = <(String, Position), Future<Set<ResolvedClass>>>{};

  /// Resolves the annotations among [tokens] and the classes among [symbols],
  /// the semantic tokens and the document symbols of the open file [path] at
  /// [relativePath], so that [annotationsOf] and [supertypesOf] can return
  /// them.
  Future<void> resolve(
    LspClient client,
    String path,
    String relativePath,
    List<SemanticToken> tokens,
    List<DocumentSymbol> symbols,
  ) async {
    final lookups = _entryPoints.lookupsIn(relativePath);
    if (lookups.isEmpty) {
      return;
    }
    final config = _packages.configOf(p.dirname(path));
    // One name written the same way names one class everywhere in a file,
    // such as `JsonKey` in `@JsonKey(...)` on every field.
    final constructorDefinitions = <String, Future<List<Location>>>{};
    await Future.wait([
      for (final name in tokens.annotationNames())
        if (name.readsConstant
            ? lookups.contains(ServerLookup.constantClasses)
            : lookups.contains(ServerLookup.annotationClasses))
          _resolveAnnotation(
            client,
            config,
            path,
            name,
            name.readsConstant
                ? client.definition(File(path).uri, name.token.start)
                : constructorDefinitions[name.written] ??= client.definition(
                    File(path).uri,
                    name.token.start,
                  ),
          ),
      if (lookups.contains(ServerLookup.supertypes))
        for (final symbol in symbols.where((s) => s.kind == .class$))
          _resolveClass(client, config, path, symbol),
    ]);
  }

  /// Returns the annotations among [leadingMetadata], the doc comment and
  /// annotation tokens of a declaration in [path].
  List<ResolvedAnnotation> annotationsOf(
    String path,
    Iterable<SemanticToken> leadingMetadata,
  ) => [
    for (final token in leadingMetadata) ...?_byAnnotation[(path, token.start)],
  ];

  /// Returns all the supertypes of the class [symbol] in [path].
  Set<ResolvedClass> supertypesOf(String path, DocumentSymbol symbol) =>
      _byClassName[(path, symbol.selectionRange.start)] ?? const {};

  /// Records the annotation called [name], whose [definitions] are those of
  /// its name. Records nothing when its class can't be resolved.
  Future<void> _resolveAnnotation(
    LspClient client,
    PackageConfig? config,
    String path,
    AnnotationName name,
    Future<List<Location>> definitions,
  ) async {
    final (:token, :readsConstant, written: _) = name;
    try {
      final classes = await Future.wait([
        for (final definition in await definitions)
          if (readsConstant)
            _heldBy(client, config, definition)
          else
            _declaredAt(client, config, definition),
      ]);
      _byAnnotation[(path, token.start)] = [
        for (final (:type, :supertypes) in classes.flattened)
          .new(type, supertypes, readsConstant: readsConstant),
      ];
    } on LspRequestException catch (e) {
      recordProblem(
        _unresolvedAnnotation,
        e,
        path: path,
        position: token.start,
      );
    }
  }

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

  /// Returns the classes declared at [definition] with their supertypes. For
  /// a typedef, which declares no class, they are those of the type that it
  /// names.
  Future<List<_Hierarchy>> _declaredAt(
    LspClient client,
    PackageConfig? config,
    Location definition,
  ) => _byDefinition[(definition.uri, definition.range.start)] ??= () async {
    final items = await client.typeHierarchyItems(
      .parse(definition.uri),
      definition.range.start,
    );
    return items.isEmpty
        ? await _heldBy(client, config, definition)
        : await Future.wait([
            for (final item in items) _hierarchyOf(client, config, item),
          ]);
  }();

  /// Returns the classes of the objects that the constant declared at
  /// [definition] holds, with their supertypes: `Preview` for
  /// `const preview = Preview();`. It follows a constant that holds another
  /// one, and a typedef, whose value is the type that it names. Returns
  /// nothing for a value that no constructor call creates, such as a list.
  Future<List<_Hierarchy>> _heldBy(
    LspClient client,
    PackageConfig? config,
    Location definition,
  ) => _byConstant[(definition.uri, definition.range.start)] ??= () async {
    final path = SourceIndex.pathOf(definition.uri);
    final value = valueNameAfter(
      _sources,
      path,
      await _sources.semanticTokensOf(client, path),
      definition.range.start,
    );
    final resolveValue = switch (value?.type) {
      'class' || 'type' => _declaredAt,
      'property' || 'variable' => _heldBy,
      _ => null,
    };
    if (value == null || resolveValue == null) {
      return const <_Hierarchy>[];
    }
    final definitions = await client.definition(
      .parse(definition.uri),
      value.start,
    );
    final classes = await Future.wait([
      for (final definition in definitions)
        resolveValue(client, config, definition),
    ]);
    return classes.flattened.toList();
  }();

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
