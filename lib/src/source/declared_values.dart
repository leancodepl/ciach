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
/// at [name] in [path]: `Plain` in `typedef AliasPlain = Plain;`. Returns
/// `null` when anything but an import prefix comes between the `=` and the
/// name. [tokens] are the semantic tokens of [path].
SemanticToken? valueNameAfter(
  SourceIndex sources,
  String path,
  List<SemanticToken> tokens,
  Position name,
) {
  final content = sources.content(path);
  // The server gives `=` no token, so it is found in the text. It comes after
  // the type parameters of a typedef, whose bounds can't hold one.
  final equals = sources
      .offsetOf(path, name)
      ?.let((offset) => content.indexOfOrNull('=', offset));
  if (equals == null) {
    return null;
  }
  final value = tokens
      .skip(tokens.firstIndexAtOrAfter(sources.positionOf(path, equals)))
      .firstWhereOrNull((token) => !token.isKeyword && !token.isImportPrefix);
  if (value == null ||
      !_beforeValue.hasMatch(
        content.substring(equals + 1, sources.offsetOf(path, value.start)),
      )) {
    return null;
  }
  return value;
}

/// Matches what may come between the `=` and the name of the type: an import
/// prefix. A regex reads the text there because the server gives neither `=`
/// nor `.` a token.
final _beforeValue = RegExp(r'^\s*(?:[A-Za-z_$][\w$]*\s*\.\s*)?$');
