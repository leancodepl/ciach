/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// Returns the token that names the type after the `=` of the typedef named
/// at [name] in [path]: `Plain` in `typedef AliasPlain = Plain;` or
/// `typedef AliasPlain = prefix.Plain;`. [tokens] are the semantic tokens of
/// [path].
SemanticToken? typeNamedBy(
  SourceIndex sources,
  String path,
  List<SemanticToken> tokens,
  Position name,
) {
  // The server gives `=` no token, so it is found in the text. It comes after
  // the type parameters, whose bounds can't hold one.
  final equals = sources
      .offsetOf(path, name)
      ?.let((offset) => sources.content(path).indexOfOrNull('=', offset));
  return equals?.let(
    (equals) => tokens
        .skip(tokens.firstIndexAtOrAfter(sources.positionOf(path, equals)))
        .firstWhereOrNull((token) => !token.isImportPrefix),
  );
}
