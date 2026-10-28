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

import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

/// The class names of the annotations in the scanned files.
final class AnnotationTypes {
  /// The names of each annotation's class and of all its supertypes, by the
  /// file and the position of the class name in the annotation.
  final _byPath = <String, Map<Position, Set<String>>>{};

  /// The names of a class and of all its supertypes, by the file and the
  /// position of the class's name in its declaration.
  final _byClass = <(String, Position), Future<Set<String>>>{};

  /// Resolves the annotations among [tokens], the semantic tokens of the open
  /// file [path], for [of].
  Future<void> resolve(
    LspClient client,
    String path,
    List<SemanticToken> tokens,
  ) async {
    final uri = File(path).uri;
    // The analysis server marks the class name of an annotation that calls a
    // constructor as a `class` token. An annotation that reads a constant,
    // such as `@override`, has a `property` token instead.
    final classNames = tokens.where(
      (token) =>
          token.type == 'class' && token.modifiers.contains('annotation'),
    );
    final resolved = await Future.wait([
      for (final token in classNames) _typeNames(client, uri, token),
    ]);
    _byPath[path] = {
      for (final (:token, :names) in resolved)
        if (names.isNotEmpty) token.start: names,
    };
  }

  /// Returns the names of the classes of the annotations among
  /// [leadingMetadata], the doc comment and annotation tokens of a declaration
  /// in [path], and of all their supertypes.
  Set<String> of(String path, Iterable<SemanticToken> leadingMetadata) => {
    for (final token in leadingMetadata) ...?_byPath[path]?[token.start],
  };

  /// Returns [token] with the names of its class and of all the supertypes of
  /// that class, or with no names when the class can't be resolved.
  Future<({SemanticToken token, Set<String> names})> _typeNames(
    LspClient client,
    Uri uri,
    SemanticToken token,
  ) async {
    try {
      final names = <String>{};
      for (final definition in await client.definition(uri, token.start)) {
        final classes = await client.typeHierarchyItems(
          .parse(definition.uri),
          definition.range.start,
        );
        for (final item in classes) {
          names.addAll(await _supertypeNames(client, item));
        }
      }
      return (token: token, names: names);
    } on LspRequestException catch (e) {
      recordProblem(
        _unresolvedAnnotation,
        e,
        path: uri.toFilePath(),
        position: token.start,
      );
      return (token: token, names: const <String>{});
    }
  }

  /// Returns the names of [item] and of all its supertypes.
  Future<Set<String>> _supertypeNames(
    LspClient client,
    TypeHierarchyItem item,
  ) => _byClass[(item.uri, item.selectionRange.start)] ??= () async {
    final supertypes = await client.supertypes(item);
    final names = await Future.wait([
      for (final supertype in supertypes) _supertypeNames(client, supertype),
    ]);
    return {item.name, for (final set in names) ...set};
  }();
}
