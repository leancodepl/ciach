/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// A minimal Dart lexer, just rich enough for the structural checks the finder
/// needs (constructor shapes, pattern matches, enum-value iteration). It drops
/// whitespace, comments, and string literals so keywords and brackets can be
/// matched without tripping over a `case` that only appears inside a comment or
/// string — but it is deliberately *not* a full parser.
library;

/// Opening bracket punctuation.
const _openers = {'(', '[', '{'};

/// Closing bracket punctuation, paired positionally with [_openers].
const _closers = {')', ']', '}'};

/// A single lexical token: a source span plus whether it is an identifier /
/// keyword (`isWord`) or a single punctuation character. Whitespace, comments,
/// and string literals are dropped during tokenization.
final class Token {
  const Token({
    required this.start,
    required this.end,
    required this.isWord,
    required this.value,
  });

  final int start;
  final int end;
  final bool isWord;
  final String value;

  /// Whether this token is an opening bracket (`(`, `[`, `{`).
  bool get isOpener => !isWord && _openers.contains(value);

  /// Whether this token is a closing bracket (`)`, `]`, `}`).
  bool get isCloser => !isWord && _closers.contains(value);
}

/// The byte offset of the start of each line in [content] (index 0 is offset
/// 0). Used to translate LSP line/character positions into absolute offsets.
List<int> computeLineStarts(String content) {
  final starts = <int>[0];
  for (var i = 0; i < content.length; i++) {
    if (content[i] == '\n') {
      starts.add(i + 1);
    }
  }
  return starts;
}

/// Splits [content] into [Token]s, skipping whitespace, `//` and (nesting)
/// `/* */` comments, and every string-literal form (single/double,
/// triple-quoted, raw, and `${…}`/`$id` interpolation). Everything else is
/// emitted as either a word token or a single-character punctuation token.
List<Token> tokenize(String content) {
  final tokens = <Token>[];
  final n = content.length;
  var i = 0;
  while (i < n) {
    final ch = content[i];
    if (ch case ' ' || '\t' || '\n' || '\r') {
      i++;
      continue;
    }
    if (ch == '/' && i + 1 < n && content[i + 1] == '/') {
      i += 2;
      while (i < n && content[i] != '\n') {
        i++;
      }
      continue;
    }
    if (ch == '/' && i + 1 < n && content[i + 1] == '*') {
      i = _skipBlockComment(content, i);
      continue;
    }
    if ((ch == 'r' || ch == 'R') &&
        i + 1 < n &&
        (content[i + 1] == "'" || content[i + 1] == '"')) {
      i = _skipString(content, i + 1, raw: true);
      continue;
    }
    if (ch == "'" || ch == '"') {
      i = _skipString(content, i, raw: false);
      continue;
    }
    if (_isIdentStart(ch)) {
      final start = i;
      i++;
      while (i < n && _isIdentPart(content[i])) {
        i++;
      }
      tokens.add(
        Token(
          start: start,
          end: i,
          isWord: true,
          value: content.substring(start, i),
        ),
      );
      continue;
    }
    tokens.add(Token(start: i, end: i + 1, isWord: false, value: ch));
    i++;
  }
  return tokens;
}

/// The index of the token whose span starts exactly at [offset], or `null`
/// if none does. Tokens are ordered by start, so this is a binary search.
int? tokenIndexAt(List<Token> tokens, int offset) {
  var lo = 0;
  var hi = tokens.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    final start = tokens[mid].start;
    if (start == offset) {
      return mid;
    }
    if (start < offset) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return null;
}

/// Walking backward from [from], the index of the nearest enclosing (not yet
/// closed) opening bracket, or `null` if the scan runs off the start.
int? enclosingOpener(List<Token> tokens, int from) {
  var depth = 0;
  for (var k = from; k >= 0; k--) {
    final t = tokens[k];
    if (t.isCloser) {
      depth++;
    } else if (t.isOpener) {
      if (depth == 0) {
        return k;
      }
      depth--;
    }
  }
  return null;
}

/// The index of the `(` matching the `)` at [closeIndex], or `null`.
int? matchingOpenParen(List<Token> tokens, int closeIndex) {
  var depth = 0;
  for (var k = closeIndex; k >= 0; k--) {
    final t = tokens[k];
    if (t.isCloser) {
      depth++;
    } else if (t.isOpener) {
      depth--;
      if (depth == 0) {
        return t.value == '(' ? k : null;
      }
    }
  }
  return null;
}

bool _isIdentStart(String ch) =>
    (ch.compareTo('a') >= 0 && ch.compareTo('z') <= 0) ||
    (ch.compareTo('A') >= 0 && ch.compareTo('Z') <= 0) ||
    ch == '_' ||
    ch == r'$';

bool _isIdentPart(String ch) =>
    _isIdentStart(ch) || (ch.compareTo('0') >= 0 && ch.compareTo('9') <= 0);

/// Skips a (possibly nested) `/* … */` block comment starting at [from],
/// returning the index just past it.
int _skipBlockComment(String content, int from) {
  final n = content.length;
  var i = from + 2;
  var depth = 1;
  while (i < n && depth > 0) {
    if (content[i] == '/' && i + 1 < n && content[i + 1] == '*') {
      depth++;
      i += 2;
    } else if (content[i] == '*' && i + 1 < n && content[i + 1] == '/') {
      depth--;
      i += 2;
    } else {
      i++;
    }
  }
  return i;
}

/// Skips a string literal whose opening quote is at [from], returning the
/// index just past the closing quote. Handles triple quotes, escapes, and —
/// unless [raw] — `${…}`/`$id` interpolation (whose braces and nested
/// strings are matched so a `}` or quote inside them doesn't end the string).
int _skipString(String content, int from, {required bool raw}) {
  final n = content.length;
  final quote = content[from];
  final triple =
      from + 2 < n && content[from + 1] == quote && content[from + 2] == quote;
  var i = from + (triple ? 3 : 1);
  while (i < n) {
    final c = content[i];
    if (!raw && c == r'\') {
      i += 2;
      continue;
    }
    if (!raw && c == r'$') {
      i = _skipInterpolation(content, i);
      continue;
    }
    if (c == quote) {
      if (!triple) {
        return i + 1;
      }
      if (i + 2 < n && content[i + 1] == quote && content[i + 2] == quote) {
        return i + 3;
      }
    }
    if (!triple && c == '\n') {
      // Unterminated single-line string; stop at the newline rather than run on.
      return i;
    }
    i++;
  }
  return n;
}

/// Skips a `$`-interpolation starting at [from] (the `$`), returning the
/// index just past it. Handles both `$identifier` and brace-matched `${…}`.
int _skipInterpolation(String content, int from) {
  final n = content.length;
  if (from + 1 < n && content[from + 1] == '{') {
    var i = from + 2;
    var depth = 1;
    while (i < n && depth > 0) {
      final c = content[i];
      if (c == '{') {
        depth++;
        i++;
      } else if (c == '}') {
        depth--;
        i++;
      } else if (c == "'" || c == '"') {
        i = _skipString(content, i, raw: false);
      } else {
        i++;
      }
    }
    return i;
  }
  var i = from + 1;
  while (i < n && _isIdentPart(content[i])) {
    i++;
  }
  return i;
}
