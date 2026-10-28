/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves the class of each annotation that calls a constructor, such as
/// `@DarkPreview()`, so that an `EntryPoint.annotatedWith` rule can match a
/// subtype of the class that it names.
library;

import 'dart:io';
import 'dart:math';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

/// The classes of the annotations in the scanned files.
final class AnnotationTypes {
  AnnotationTypes(this._sources);

  final SourceIndex _sources;
  final _packages = PackageResolver();

  /// Each annotation's class and all its supertypes, by the file and the
  /// position of the class name in the annotation.
  final _byAnnotation = <(String, Position), Set<AnnotationClass>>{};

  /// The classes that a definition location declares, with all their
  /// supertypes. The same annotation in many places has the same definition.
  final _byDefinition = <(String, Position), Future<Set<AnnotationClass>>>{};

  /// A class and all its supertypes, by the file and the position of the
  /// class's name in its declaration.
  final _byClass = <(String, Position), Future<Set<AnnotationClass>>>{};

  /// Resolves the annotations among [tokens], the semantic tokens of the open
  /// file [path], so that [of] can return their classes.
  Future<void> resolve(
    LspClient client,
    String path,
    List<SemanticToken> tokens,
  ) async {
    final config = _packages.configOf(p.dirname(path));
    await Future.wait([
      for (final token in _annotationNames(tokens))
        _resolveToken(client, config, path, token),
    ]);
  }

  /// Returns the class or typedef name of each annotation among [tokens]
  /// that calls a constructor: `Preview` in `@Preview()`, and `AliasPreview`
  /// in `@prefix.AliasPreview()`.
  static Iterable<SemanticToken> _annotationNames(
    List<SemanticToken> tokens,
  ) sync* {
    for (final (i, token) in tokens.indexed) {
      if (token.isAnnotationClassName) {
        yield token;
      } else if (token.type == 'type') {
        // The server marks a typedef name with no `annotation` modifier, so
        // only its place after the `@` and an optional import prefix tells
        // that it names the annotation and not one of its type arguments.
        final before = tokens.sublist(max(0, i - 3), i).reversed.toList();
        if (switch (before) {
          [SemanticToken(text: '@'), ...] => true,
          [
            SemanticToken(text: '.'),
            SemanticToken(:final modifiers),
            SemanticToken(text: '@'),
          ]
              when modifiers.contains('importPrefix') =>
            true,
          _ => false,
        }) {
          yield token;
        }
      }
    }
  }

  /// Returns the classes of the annotations among [leadingMetadata], the doc
  /// comment and annotation tokens of a declaration in [path], and all their
  /// supertypes.
  Set<AnnotationClass> of(
    String path,
    Iterable<SemanticToken> leadingMetadata,
  ) => {
    for (final token in leadingMetadata) ...?_byAnnotation[(path, token.start)],
  };

  /// Records the class of the annotation [token] and all the supertypes of
  /// that class. Records nothing when the class can't be resolved.
  Future<void> _resolveToken(
    LspClient client,
    PackageConfig? config,
    String path,
    SemanticToken token,
  ) async {
    try {
      final definitions = await client.definition(File(path).uri, token.start);
      final classes = await Future.wait([
        for (final definition in definitions)
          _declaredAt(client, config, definition),
      ]);
      _byAnnotation[(path, token.start)] = {for (final set in classes) ...set};
    } on LspRequestException catch (e) {
      recordProblem(
        _unresolvedAnnotation,
        e,
        path: path,
        position: token.start,
      );
    }
  }

  /// Returns the classes declared at [definition] and all their supertypes.
  /// For a typedef, which declares no class, they are those of the type that
  /// it names.
  Future<Set<AnnotationClass>> _declaredAt(
    LspClient client,
    PackageConfig? config,
    Location definition,
  ) => _byDefinition[(definition.uri, definition.range.start)] ??= () async {
    final items = await client.typeHierarchyItems(
      .parse(definition.uri),
      definition.range.start,
    );
    final classes = await Future.wait([
      for (final item in items) _withSupertypes(client, config, item),
      if (items.isEmpty)
        for (final aliased in await _aliasedTypes(client, definition))
          _declaredAt(client, config, aliased),
    ]);
    return {for (final set in classes) ...set};
  }();

  /// Returns where the type that the typedef named at [name] names is
  /// declared: `Plain` for `typedef AliasPlain = Plain;`. Returns nothing
  /// when [name] doesn't name a typedef.
  Future<List<Location>> _aliasedTypes(LspClient client, Location name) async {
    final path = SourceIndex.pathOf(name.uri);
    if (!_sources.hasSemanticTokens(path)) {
      _sources.cacheSemanticTokens(
        path,
        await semanticTokensOrEmpty(client, _sources, path),
      );
    }
    final tokens = _sources.semanticTokens(path)!;
    final offset = _sources.offsetOf(path, name.range.start);
    if (tokens.startingAt(name.range.start)?.type != 'type' || offset == null) {
      return const [];
    }
    // The server gives `=` no token, so it is found in the text. It comes
    // after the type parameters, whose bounds can't hold one.
    final aliased = _sources
        .content(path)
        .indexOfOrNull('=', offset)
        ?.let(
          (equals) => tokens
              .skip(
                tokens.firstIndexAtOrAfter(_sources.positionOf(path, equals)),
              )
              .firstWhereOrNull((t) => t.type == 'class' || t.type == 'type'),
        );
    return await aliased?.let(
          (aliased) => client.definition(.parse(name.uri), aliased.start),
        ) ??
        const [];
  }

  /// Returns the class of [item] and all its supertypes. Their libraries are
  /// the `package:` URIs that [config] gives them.
  Future<Set<AnnotationClass>> _withSupertypes(
    LspClient client,
    PackageConfig? config,
    TypeHierarchyItem item,
  ) => _byClass[(item.uri, item.selectionRange.start)] ??= () async {
    final supertypes = await client.supertypes(item);
    final classes = await Future.wait([
      for (final supertype in supertypes)
        _withSupertypes(client, config, supertype),
    ]);
    return {
      // The server names a generic class `Story<T>`.
      AnnotationClass(
        item.name.withoutTypeArguments,
        config?.toPackageUri(.parse(item.uri)),
      ),
      for (final set in classes) ...set,
    };
  }();
}
