/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Comment blanking for the directive rewriting after `--remove`, which runs
/// once the analysis server is gone.
library;

import 'package:ciach/src/extensions.dart';

final _nonNewline = RegExp(r'[^\n]');

/// [content] with `//` and `/* */` comments blanked to spaces; strings and
/// offsets preserved.
String stripComments(String content) {
  final n = content.length;
  final out = StringBuffer();
  var i = 0;
  while (i < n) {
    final start = i;
    if (_stringLiteralEnd(content, i) case final end?) {
      out.write(content.substring(start, end));
      i = end;
      continue;
    }
    switch (content[i]) {
      case '/' when i + 1 < n && content[i + 1] == '/':
        i = content.indexOfOrNull('\n', i) ?? n;
        out.write(content.substring(start, i).replaceAll(_nonNewline, ' '));
      case '/' when i + 1 < n && content[i + 1] == '*':
        i = _skipBlockComment(content, i);
        out.write(content.substring(start, i).replaceAll(_nonNewline, ' '));
      default:
        out.write(content[i]);
        i++;
    }
  }
  return out.toString();
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

bool _isQuote(String c) => c == "'" || c == '"';

int? _stringLiteralEnd(String content, int i) => switch (content[i]) {
  final c when _isQuote(c) => _skipString(content, i, raw: false),
  'r' when i + 1 < content.length && _isQuote(content[i + 1]) => _skipString(
    content,
    i + 1,
    raw: true,
  ),
  _ => null,
};

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
