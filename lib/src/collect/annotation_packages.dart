/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/hover_text.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

const _unresolvedAnnotation =
    'Could not find the package that declares this annotation; the declaration that it annotates may be reported.';

/// The packages that declare the annotations that the entry-point rules name,
/// such as `dart:core` for `pragma` in `@pragma('vm:entry-point')`.
final class AnnotationPackages {
  AnnotationPackages(this._entryPoints);

  final EntryPoints _entryPoints;

  /// The package of each annotation, by the file and the position of the name
  /// that the annotation's `@` is followed by.
  final _byName = <(String, Position), String>{};

  /// Resolves the annotations among [tokens], the semantic tokens of the open
  /// file [path] at [relativePath], whose name a rule that applies to the file
  /// names, so that [packagesOf] can return their packages.
  Future<void> resolve(
    LspClient client,
    String path,
    String relativePath,
    List<SemanticToken> tokens,
  ) async {
    final names = _entryPoints.annotationNamesIn(relativePath);
    await Future.wait([
      for (final token in tokens)
        if (names.any(token.isAnnotationNamed)) _resolve(client, path, token),
    ]);
  }

  /// Returns the package of each annotation among [leadingMetadata], the doc
  /// comment and annotation tokens of a declaration in [path], by the
  /// position of its name.
  Map<Position, String> packagesOf(
    String path,
    Iterable<SemanticToken> leadingMetadata,
  ) => {
    for (final token in leadingMetadata)
      token.start: ?_byName[(path, token.start)],
  };

  /// Records the package of the annotation whose name is [name]. Records
  /// nothing when the server names no package.
  Future<void> _resolve(
    LspClient client,
    String path,
    SemanticToken name,
  ) async {
    try {
      final hover = await client.hover(File(path).uri, name.start);
      if (hover?.let(declaringPackageIn) case final package?) {
        _byName[(path, name.start)] = package;
      }
    } on LspRequestException catch (e) {
      recordProblem(_unresolvedAnnotation, e, path: path, position: name.start);
    }
  }
}
