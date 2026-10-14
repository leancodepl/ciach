/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Text scanning for when the analysis server can't help: comment blanking
/// for the directive rewriting after `--remove`, which runs once the server is
/// gone, and whitespace skipping.
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
    if (stringLiteralEnd(content, i) case final end?) {
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

/// The `//` comments of [content], doc comments included, by offset: none in a
/// string or a block comment.
Iterable<({int offset, String text})> lineComments(String content) sync* {
  final n = content.length;
  var i = 0;
  while (i < n) {
    if (stringLiteralEnd(content, i) case final end?) {
      i = end;
    } else if (content.startsWith('//', i)) {
      final end = content.indexOfOrNull('\n', i) ?? n;
      yield (offset: i, text: content.substring(i, end));
      i = end;
    } else if (content.startsWith('/*', i)) {
      i = _skipBlockComment(content, i);
    } else {
      i++;
    }
  }
}

/// The index of the first character at or after [from] that is neither
/// whitespace nor in a comment.
int skipCommentsAndWhitespace(String content, int from) {
  var i = from;
  while (i < content.length) {
    if (content.startsWith('//', i)) {
      i = content.indexOfOrNull('\n', i) ?? content.length;
    } else if (content.startsWith('/*', i)) {
      i = _skipBlockComment(content, i);
    } else if (content[i].trim().isEmpty) {
      i++;
    } else {
      break;
    }
  }
  return i;
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

/// The index just past the string literal that starts at [i], or `null` when
/// none does.
int? stringLiteralEnd(String content, int i) => switch (content[i]) {
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
  final quote = content[from];
  final triple = _isTripleQuote(content, from, quote);
  var i = from + (triple ? 3 : 1);
  while (i < content.length) {
    final c = content[i];
    switch (c) {
      case r'\' when !raw:
        i += 2;
      case r'$' when !raw:
        i = _skipInterpolation(content, i);
      case _ when c == quote && !triple:
        return i + 1;
      case _ when _isTripleQuote(content, i, quote):
        return i + 3;
      // Unterminated single-line string; stop at the newline rather than run on.
      case '\n' when !triple:
        return i;
      default:
        i++;
    }
  }
  return content.length;
}

bool _isTripleQuote(String content, int at, String quote) =>
    content.startsWith(quote * 3, at);

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

/// The offset at which each line of [content] starts.
List<int> lineStartsOf(String content) => [
  0,
  for (var i = 0; i < content.length; i++)
    if (content[i] == '\n') i + 1,
];

/// An analyzer `// ignore:` comment, which applies to the next line only.
final analyzerIgnore = RegExp(r'^//\s*ignore:');

/// A comment another tool reads, such as `// coverage:ignore-start`,
/// `// ciach:ignore-end` or `// dart format off`. It may pair with a comment
/// elsewhere in the file.
bool isToolDirective(String comment) => _toolDirective.hasMatch(comment);

final _toolDirective = RegExp(r'^//\s*([\w.-]+:\S|dart format\b)');

/// If nothing but whitespace, or a `//` comment, follows [end] on its line,
/// extends it past the line break — so deleting a declaration leaves neither a
/// blank line nor its trailing comment behind. That comment, such as an
/// `// ignore:`, would otherwise apply to the line after it. A tool directive
/// other than `// ignore:` stays, so a range it opens or closes keeps both
/// ends.
int consumeLineEnd(String content, int end) {
  final nextNewline = content.indexOfOrNull('\n', end);
  final restOfLine = content.substring(end, nextNewline ?? content.length);
  if (nextNonWhitespace(restOfLine, 0) case final i?) {
    final comment = restOfLine.substring(i);
    if (!comment.startsWith('//') ||
        (isToolDirective(comment) && !analyzerIgnore.hasMatch(comment))) {
      return end;
    }
  }
  return nextNewline?.let((newline) => newline + 1) ?? content.length;
}

/// The index of the first non-whitespace character at or after [from], if
/// any.
int? nextNonWhitespace(String content, int from) {
  for (var i = from; i < content.length; i++) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

/// The index of the last non-whitespace character before [before], if any.
int? previousNonWhitespace(String content, int before) {
  for (var i = before - 1; i >= 0; i--) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

bool _isWhitespace(String ch) => switch (ch) {
  ' ' || '\t' || '\n' || '\r' => true,
  _ => false,
};
