/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Builds the tokens of a resolved file as the analysis server's semantic
/// tokens list them: every identifier, keyword, literal and comment, with no
/// punctuation but the `@` and the parentheses of an annotation.
///
/// It follows `DartUnitHighlightsComputer` and `SemanticTokenEncoder` in the
/// analysis server, whose tokens ciach read over LSP before, for what ciach
/// reads: where each token is, whether it is a comment, a doc comment, a
/// keyword or a string, whether it names a class or a property, and whether
/// it declares something or names an annotation. Other identifiers get a
/// type from their element, which can differ from the server's.
library;

import 'dart:collection';
import 'dart:math';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/analysis/highlight_regions.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// Returns the tokens of [unit], whose text is [content] and whose lines
/// [lineInfo] holds, in order.
List<SemanticToken> unitTokens(
  CompilationUnit unit,
  String content,
  LineInfo lineInfo,
) {
  final visitor = HighlightRegions()..visitCompilationUnit(unit);
  final regions = visitor.regions;
  final named = {
    for (final region in regions) region.offset,
    ...visitor.covered,
  };
  for (Token? token = unit.beginToken; token != null; token = token.next) {
    for (
      Token? comment = token.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      regions.add(
        .of(comment, 'comment', {if (_isDocComment(comment)) 'documentation'}),
      );
    }
    if (token.isEof) {
      break;
    }
    if (!named.contains(token.offset)) {
      if (_typeOf(token) case final type?) {
        regions.add(.of(token, type));
      }
    }
  }
  regions.sort(HighlightRegion.byPlace);
  final lines = content.split('\n');
  return [
    for (final region in _withoutOverlaps(regions))
      ..._onEachLine(region, lineInfo, lines),
  ];
}

/// The type of a [token] that names nothing: a keyword, a literal, or `null`
/// for punctuation.
String? _typeOf(Token token) => switch (token) {
  Token(type: .STRING) => 'string',
  Token(type: .INT || .DOUBLE || .HEXADECIMAL) => 'number',
  Token(keyword: .TRUE || .FALSE) => 'boolean',
  Token(keyword: _?) => 'keyword',
  Token(type: .IDENTIFIER) => 'source',
  _ => null,
};

/// Whether [comment] is a `///` or `/**` doc comment.
bool _isDocComment(Token comment) => switch (comment.type) {
  .SINGLE_LINE_COMMENT => comment.lexeme.startsWith('///'),
  .MULTI_LINE_COMMENT => comment.lexeme.startsWith('/**'),
  _ => false,
};

/// [sorted] with each region that holds others split around them, as the
/// server's `splitOverlappingTokens` does: `@pragma(` around `pragma` gives
/// `@`, `pragma` and `(`.
Iterable<HighlightRegion> _withoutOverlaps(List<HighlightRegion> sorted) sync* {
  final open = ListQueue<HighlightRegion>();
  Iterable<HighlightRegion> close(int from, int to) sync* {
    var start = from;
    while (open.isNotEmpty) {
      final last = open.last;
      final end = min(last.end, to);
      if (end > start) {
        yield .new(start, end - start, last.type, last.modifiers);
        start = end;
      }
      if (last.end > to) {
        return;
      }
      open.removeLast();
    }
  }

  if (sorted.isEmpty) {
    return;
  }
  var from = sorted.first.offset;
  for (final region in sorted) {
    yield* close(from, region.offset);
    open.addLast(region);
    from = region.offset;
  }
  yield* close(from, open.first.end);
}

/// The token of [region] on each line of [lines] that it spans. Like the
/// server, it splits the region at line starts and lets each part but the
/// last run to the start of the next line, and like ciach's decoder of the
/// server's tokens, it drops a part that runs past the end of its line, so a
/// region that spans lines keeps only its last line.
Iterable<SemanticToken> _onEachLine(
  HighlightRegion region,
  LineInfo lineInfo,
  List<String> lines,
) sync* {
  final start = lineInfo.positionOf(region.offset);
  final end = lineInfo.positionOf(region.end);
  for (var line = start.line; line <= end.line; line++) {
    final from = line == start.line ? start.character : 0;
    final to = line == end.line
        ? end.character
        : lineInfo.getOffsetOfLine(line + 1) - lineInfo.getOffsetOfLine(line);
    if (to <= lines[line].length) {
      yield .new(
        line: line,
        character: from,
        length: to - from,
        type: region.type,
        modifiers: region.modifiers,
        text: lines[line].substring(from, to),
      );
    }
  }
}
