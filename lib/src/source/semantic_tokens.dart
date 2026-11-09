/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/source/locations.dart';

/// A token on one line of a file, classified as the semantic tokens of the
/// analysis server classify it. A comment or string that spans lines is one
/// token on its last line. A `[Foo]` link in a doc comment is its own `class`
/// token, not part of the comment.
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

  /// The value of this string literal without its quotes, such as
  /// `vm:entry-point` for `'vm:entry-point'`, or `null` when this is not a
  /// string literal or has an escape or an interpolation.
  String? get stringValue => type == 'string'
      ? _plainString.firstMatch(text)?.namedGroup('value')
      : null;
}

/// A string literal with no escape and no interpolation, in any quotes:
/// `'a'`, `"a"`, `r'a'` or `'''a'''`. The semantic token of a string
/// literal holds its source text, quotes included.
final _plainString = RegExp(
  r'''^r?(?<quote>'{3}|"{3}|'|")(?<value>[^\\$'"]*)\k<quote>$''',
);

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
}
