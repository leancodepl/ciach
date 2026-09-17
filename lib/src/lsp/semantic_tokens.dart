import 'package:ciach/src/symbols.dart';
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
          SemanticTokensLegend(
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

  Position get start => Position(line: line, character: character);

  int get end => character + length;

  bool get isDocComment =>
      type == 'comment' && modifiers.contains('documentation');

  bool get isKeyword => type == 'keyword';

  /// Whether this is the name of an `@[name]` annotation.
  bool isAnnotationNamed(String name) =>
      modifiers.contains('annotation') && text == name;
}

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
      SemanticToken(
        line: line,
        character: character,
        length: length,
        type: legend.tokenTypes[typeIndex],
        modifiers: {
          for (var bit = 0; bit < legend.tokenModifiers.length; bit++)
            if ((modifierBits >> bit) & 1 == 1) legend.tokenModifiers[bit],
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
    final i = firstIndexAtOrAfter(Position(line: line, character: 0));
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
}
