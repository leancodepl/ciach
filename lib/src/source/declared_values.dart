/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// Returns the token that names the type after the `=` of the typedef named
/// at [name] in [path]: `Plain` in `typedef AliasPlain = Plain;` or
/// `typedef AliasPlain = prefix.Plain;`. [tokens] are the semantic tokens of
/// [path].
SemanticToken? typeNamedBy(
  SourceIndex sources,
  String path,
  List<SemanticToken> tokens,
  Position name,
) => sources
    .offsetOf(path, name)
    // The server gives `=` no token, so it is found in the text. It comes
    // after the type parameters, whose bounds can't hold one.
    ?.let((offset) => sources.content(path).indexOfOrNull('=', offset))
    ?.let(
      (equals) => tokens
          .skip(tokens.firstIndexAtOrAfter(sources.positionOf(path, equals)))
          .firstWhereOrNull((token) => !token.isImportPrefix),
    );
