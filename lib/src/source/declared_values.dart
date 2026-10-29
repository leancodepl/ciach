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

/// Returns the token that names the value after the `=` of the typedef or
/// constant named at [name] in [path]: `Plain` in
/// `typedef AliasPlain = Plain;`, `Story` in `const story = Story();` and
/// `held` in `const story = Holder.held;`. Returns `null` when anything but
/// `const`, `new` and an import prefix comes between the `=` and the name,
/// as `[` does in `const stories = [Story()];`. [tokens] are the semantic
/// tokens of [path].
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
      .firstWhereOrNull(
        (token) =>
            !token.isKeyword && !token.modifiers.contains('importPrefix'),
      );
  if (value == null ||
      !_beforeValue.hasMatch(
        content.substring(equals + 1, sources.offsetOf(path, value.start)),
      )) {
    return null;
  }
  // In `Holder.held`, the value is the constant `held`.
  final next = tokens.elementAtOrNull(
    tokens.firstIndexAtOrAfter(value.start) + 1,
  );
  return switch (next) {
    SemanticToken(type: 'property')
        when _dot.hasMatch(
          content.substring(
            sources.offsetOf(path, value.start)! + value.length,
            sources.offsetOf(path, next.start),
          ),
        ) =>
      next,
    _ => value,
  };
}

/// Matches what may come between the `=` and the name of the value: `const`,
/// `new` and an import prefix. Regexes read the text around the value because
/// the server gives none of `=`, `.`, `[` and `(` a token there.
final _beforeValue = RegExp(
  r'^\s*(?:(?:const|new)\s+)?(?:[A-Za-z_$][\w$]*\s*\.\s*)?$',
);

/// Matches the `.` between a class name and a static constant.
final _dot = RegExp(r'^\s*\.\s*$');
