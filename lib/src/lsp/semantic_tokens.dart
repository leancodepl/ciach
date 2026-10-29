import 'dart:math';

import 'package:ciach/src/source/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, Range;

/// The token type and modifier names a `semanticTokens` response indexes into.
final class SemanticTokensLegend {
  const SemanticTokensLegend({
    required this.tokenTypes,
    required this.tokenModifiers,
  });

  /// The legend from the server's `initialize` capabilities, or [empty].
  factory SemanticTokensLegend.fromCapabilities(Map<String, Object?> json) =>
      switch (json['semanticTokensProvider']) {
        {
          'legend': {
            'tokenTypes': final List<Object?> types,
            'tokenModifiers': final List<Object?> modifiers,
          },
        } =>
          .new(
            tokenTypes: [for (final t in types) '$t'],
            tokenModifiers: [for (final m in modifiers) '$m'],
          ),
        _ => empty,
      };

  static const empty = SemanticTokensLegend(tokenTypes: [], tokenModifiers: []);

  final List<String> tokenTypes;
  final List<String> tokenModifiers;
}

/// A token on one line of a file, as classified by the analysis server. A
/// multi-line comment or string arrives as one token per line. A `[Foo]` link
/// in a doc comment is its own `class` token, not part of the comment.
final class SemanticToken {
  const SemanticToken({
    required this.line,
    required this.character,
    required this.length,
    required this.type,
    required this.modifiers,
    required this.text,
  });

  final int line;
  final int character;
  final int length;
  final String type;
  final Set<String> modifiers;

  final String text;

  Position get start => .new(line: line, character: character);

  int get end => character + length;

  bool get isComment => type == 'comment';

  bool get isDocComment => isComment && modifiers.contains('documentation');

  bool get isKeyword => type == 'keyword';

  bool get isDeclaration => modifiers.contains('declaration');

  /// Whether this is the name of an `@[name]` annotation.
  bool isAnnotationNamed(String name) =>
      modifiers.contains('annotation') && text == name;
}

/// The name that follows the `@` of an annotation, as
/// [SemanticTokenLookup.annotationNames] returns it.
typedef AnnotationName = ({
  /// The token of the name: the class or typedef whose constructor the
  /// annotation calls, or the constant that it reads.
  SemanticToken token,

  /// The name as written, with its import prefix: `previews.Preview`.
  String written,

  /// Whether the annotation reads a constant, as `@preview` and
  /// `@Holder.held` do, rather than calling a constructor.
  bool readsConstant,
});

/// Decodes the relative-encoded [data] of a `semanticTokens/full` response.
/// Tokens outside the legend or the file are dropped.
List<SemanticToken> decodeSemanticTokens(
  List<int> data,
  SemanticTokensLegend legend,
  List<String> lines,
) {
  final tokens = <SemanticToken>[];
  var line = 0;
  var character = 0;
  for (var i = 0; i + 4 < data.length; i += 5) {
    final deltaLine = data[i];
    if (deltaLine > 0) {
      line += deltaLine;
      character = data[i + 1];
    } else {
      character += data[i + 1];
    }
    final length = data[i + 2];
    final typeIndex = data[i + 3];
    final modifierBits = data[i + 4];
    if (typeIndex < 0 ||
        typeIndex >= legend.tokenTypes.length ||
        line < 0 ||
        line >= lines.length ||
        character < 0 ||
        character + length > lines[line].length) {
      continue;
    }
    tokens.add(
      .new(
        line: line,
        character: character,
        length: length,
        type: legend.tokenTypes[typeIndex],
        modifiers: {
          for (final (bit, tokenModifier) in legend.tokenModifiers.indexed)
            if ((modifierBits >> bit) & 1 == 1) tokenModifier,
        },
        text: lines[line].substring(character, character + length),
      ),
    );
  }
  return tokens;
}

/// Lookups over a file's tokens, which are ordered by position.
extension SemanticTokenLookup on List<SemanticToken> {
  /// The index of the first token starting at or after [position].
  int firstIndexAtOrAfter(Position position) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (this[mid].start.isBefore(position)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The first token on [line].
  SemanticToken? firstOnLine(int line) {
    final i = firstIndexAtOrAfter(.new(line: line, character: 0));
    return i < length && this[i].line == line ? this[i] : null;
  }

  /// The token starting at [position].
  SemanticToken? startingAt(Position position) {
    final i = firstIndexAtOrAfter(position);
    return i < length && this[i].start == position ? this[i] : null;
  }

  /// The last token starting within [range].
  SemanticToken? lastIn(Range range) {
    final i = firstIndexAtOrAfter(range.end) - 1;
    return i >= 0 && !this[i].start.isBefore(range.start) ? this[i] : null;
  }

  /// The tokens starting at or after [from] and before [to].
  Iterable<SemanticToken> between(Position from, Position to) =>
      skip(firstIndexAtOrAfter(from)).takeWhile((t) => t.start.isBefore(to));

  /// Returns the name of each annotation among these tokens: `Preview` in
  /// `@Preview()`, `@Preview.named()` and `@prefix.Preview()`, a typedef such
  /// as `AliasPreview` in `@AliasPreview()`, and the constants `preview` in
  /// `@preview` and `held` in `@Holder.held`.
  Iterable<AnnotationName> annotationNames() sync* {
    for (final (i, token) in indexed) {
      // The server marks the name of a constant with `annotation`, and the
      // name of a class but not of a typedef. Only a typedef name's place
      // after the `@` tells that it names the annotation and not one of its
      // type arguments.
      final readsConstant =
          token.type == 'property' && token.modifiers.contains('annotation');
      if (readsConstant ||
          ((token.type == 'class' || token.type == 'type') &&
              _followsAt(i) &&
              !_namesStaticConstant(i))) {
        final prefix = switch (sublist(max(0, i - 2), i)) {
          [
            SemanticToken(:final text, :final modifiers),
            SemanticToken(text: '.'),
          ]
              when modifiers.contains('importPrefix') =>
            '$text.',
          _ => '',
        };
        yield (
          token: token,
          written: '$prefix${token.text}',
          readsConstant: readsConstant,
        );
      }
    }
  }

  /// Whether the token at [index] comes right after an `@`, or after an `@`
  /// and an import prefix.
  bool _followsAt(int index) =>
      switch (sublist(max(0, index - 3), index).reversed.toList()) {
        [SemanticToken(text: '@'), ...] => true,
        [
          SemanticToken(text: '.'),
          SemanticToken(:final modifiers),
          SemanticToken(text: '@'),
        ]
            when modifiers.contains('importPrefix') =>
          true,
        _ => false,
      };

  /// Whether the class name at [index] is followed by a `.` and a static
  /// constant, as `Holder` in `@Holder.held` is, so that the annotation
  /// calls no constructor.
  bool _namesStaticConstant(int index) =>
      switch (skip(index + 1).take(2).toList()) {
        [SemanticToken(text: '.'), SemanticToken(type: 'property')] => true,
        _ => false,
      };
}
