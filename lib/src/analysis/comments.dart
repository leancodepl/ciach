/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The `//` comments of Dart source, read from the analyzer's tokens.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:ciach/src/analysis/dart_text.dart';

/// The `//` comments of [unit], doc comments included, in order: the offset
/// of each and its text, which runs to the end of its line.
Iterable<({int offset, String text})> lineCommentsOf(
  CompilationUnit unit,
) sync* {
  // The comments before the end of the file are those of the EOF token, whose
  // `next` is itself.
  for (var token = unit.beginToken; ; token = token.next!) {
    for (final comment in commentsBefore(token)) {
      if (comment.type == .SINGLE_LINE_COMMENT) {
        yield (offset: comment.offset, text: comment.lexeme);
      }
    }
    if (token.isEof) {
      return;
    }
  }
}

/// The comments right before [token], in order.
Iterable<Token> commentsBefore(Token token) sync* {
  for (
    Token? comment = token.precedingComments;
    comment != null;
    comment = comment.next
  ) {
    yield comment;
  }
}

/// The `//` comments of the Dart source [content], as [lineCommentsOf] reads
/// them.
List<({int offset, String text})> lineCommentsIn(String content) =>
    lineCommentsOf(parseDart(content).unit).toList();
