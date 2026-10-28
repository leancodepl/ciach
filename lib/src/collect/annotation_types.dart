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
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

/// The classes of the annotations in the scanned files.
final class AnnotationTypes {
  final _packages = PackageResolver();

  /// Each annotation's class and all its supertypes, by the file and the
  /// position of the class name in the annotation.
  final _byPath = <String, Map<Position, Set<AnnotationClass>>>{};

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
    // The analysis server marks the class name of an annotation that calls a
    // constructor as a `class` token. An annotation that reads a constant,
    // such as `@override`, has a `property` token instead.
    final classNames = tokens.where(
      (token) =>
          token.type == 'class' && token.modifiers.contains('annotation'),
    );
    final resolved = await Future.wait([
      for (final token in classNames) _classesOf(client, path, token),
    ]);
    _byPath[path] = {
      for (final (:token, :classes) in resolved)
        if (classes.isNotEmpty) token.start: classes,
    };
  }

  /// Returns the classes of the annotations among [leadingMetadata], the doc
  /// comment and annotation tokens of a declaration in [path], and all their
  /// supertypes.
  Set<AnnotationClass> of(
    String path,
    Iterable<SemanticToken> leadingMetadata,
  ) => {for (final token in leadingMetadata) ...?_byPath[path]?[token.start]};

  /// Returns [token] with its class and all the supertypes of that class, or
  /// with no classes when the class can't be resolved.
  Future<({SemanticToken token, Set<AnnotationClass> classes})> _classesOf(
    LspClient client,
    String path,
    SemanticToken token,
  ) async {
    try {
      final classes = <AnnotationClass>{};
      for (final definition in await client.definition(
        File(path).uri,
        token.start,
      )) {
        final items = await client.typeHierarchyItems(
          .parse(definition.uri),
          definition.range.start,
        );
        for (final item in items) {
          classes.addAll(await _withSupertypes(client, path, item));
        }
      }
      return (token: token, classes: classes);
    } on LspRequestException catch (e) {
      recordProblem(
        _unresolvedAnnotation,
        e,
        path: path,
        position: token.start,
      );
      return (token: token, classes: const <AnnotationClass>{});
    }
  }

  /// Returns the class of [item] and all its supertypes. Their libraries are
  /// the `package:` URIs that the package config of [path] gives them.
  Future<Set<AnnotationClass>> _withSupertypes(
    LspClient client,
    String path,
    TypeHierarchyItem item,
  ) => _byClass[(item.uri, item.selectionRange.start)] ??= () async {
    final supertypes = await client.supertypes(item);
    final classes = await Future.wait([
      for (final supertype in supertypes)
        _withSupertypes(client, path, supertype),
    ]);
    final library = _packages
        .configOf(p.dirname(path))
        ?.toPackageUri(.parse(item.uri));
    return {
      AnnotationClass(item.name, library),
      for (final set in classes) ...set,
    };
  }();
}
