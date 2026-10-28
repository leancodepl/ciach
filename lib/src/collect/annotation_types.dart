/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves the class of each annotation that calls a constructor, such as
/// `@DarkPreview()`, so that an `EntryPoint.annotatedWith` rule can match a
/// subclass of the class that it names.
library;

import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show Location, Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

/// The classes of the annotations in the scanned files.
final class AnnotationTypes {
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
  /// file [path], for [of].
  Future<void> resolve(
    LspClient client,
    String path,
    List<SemanticToken> tokens,
  ) async {
    final config = _packages.configOf(p.dirname(path));
    await Future.wait([
      for (final token in tokens.where((token) => token.isAnnotationClassName))
        _resolveToken(client, config, path, token),
    ]);
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
    ]);
    return {for (final set in classes) ...set};
  }();

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
      AnnotationClass(item.name, config?.toPackageUri(.parse(item.uri))),
      for (final set in classes) ...set,
    };
  }();
}
