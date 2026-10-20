/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analysis_server_plugin/edit/dart/correction_producer.dart';
import 'package:analysis_server_plugin/edit/dart/dart_fix_kind_priority.dart';
import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';

/// The column limit that `CLAUDE.md` splits strings at.
const _maxLineLength = 120;

/// Flags adjacent string literals whose joined line fits in 120 columns,
/// which `CLAUDE.md` wants as one literal.
///
/// The joined line is the text before the first literal on its line, the
/// joined literal, and the text after the last literal on its line: `  'a '`
/// and `'b',` on two lines join into `  'a b',`. Adjacent strings with a
/// multi-line literal or a comment between them are never flagged.
class PreferSingleStringLiteral() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_single_string_literal',
    'These adjacent strings fit in 120 columns as one literal.',
    correctionMessage: 'Try replacing them with {0}.',
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addAdjacentStrings(this, _Visitor(this, context));
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitAdjacentStrings(AdjacentStrings node) {
    if (context.currentUnit case final unit?) {
      final content = unit.content;
      if (joinedLiteral(node, content) case final joined?
          when _joinedLineLength(node, joined, content) <= _maxLineLength) {
        rule.reportAtNode(node, arguments: [joined]);
      }
    }
  }
}

/// Replaces the flagged adjacent strings with one literal.
class JoinAdjacentStrings({required super.context})
    extends ResolvedCorrectionProducer {
  static const kind = FixKind(
    'ciach_lints.fix.joinAdjacentStrings',
    DartFixKindPriority.standard,
    'Replace with {0}',
  );

  late final _joined = switch (node) {
    final AdjacentStrings strings => joinedLiteral(strings, unitResult.content),
    _ => null,
  };

  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => kind;

  @override
  List<String> get fixArguments => [?_joined];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (_joined case final joined?) {
      await builder.addDartFileEdit(
        file,
        (builder) => builder.addSimpleReplacement(range.node(node), joined),
      );
    }
  }
}

/// The one literal that says what [node] says, or `null` when one of its
/// strings is multi-line or a comment sits between two of them. [content] is
/// the file's text.
///
/// The literal is raw only when every string is raw with the same quote. It
/// is single-quoted unless its text has a `'` and no `"`, and a `$name`
/// interpolation followed by a letter, digit or `_` becomes `${name}`.
String? joinedLiteral(AdjacentStrings node, String content) {
  final strings = node.strings.whereType<SingleStringLiteral>().toList();
  if (strings.length < node.strings.length ||
      strings.any((string) => string.isMultiline) ||
      strings
          .skip(1)
          .any((string) => string.beginToken.precedingComments != null)) {
    return null;
  }
  final first = strings.first;
  if (strings.every(
    (string) => string.isRaw && string.isSingleQuoted == first.isSingleQuoted,
  )) {
    final quote = first.isSingleQuoted ? "'" : '"';
    final text = strings
        .map(
          (string) =>
              content.substring(string.contentsOffset, string.contentsEnd),
        )
        .join();
    return 'r$quote$text$quote';
  }
  final pieces = [for (final string in strings) ..._piecesOf(string, content)];
  final chars = pieces.whereType<_Char>().map((piece) => piece.char).toSet();
  final quote = chars.contains("'") && !chars.contains('"') ? '"' : "'";
  final text = [
    for (final (i, piece) in pieces.indexed)
      switch ((piece, pieces.elementAtOrNull(i + 1))) {
        (_Interpolation(:final name?), _Char(:final char))
            when _identifierPart.hasMatch(char) =>
          '\${$name}',
        (_Char(:final char), _) when _needsEscape(char, quote) => '\\$char',
        (_Char(:final char), _) => char,
        (_Escape(:final source) || _Interpolation(:final source), _) => source,
      },
  ].join();
  return '$quote$text$quote';
}

/// Whether [char] needs a backslash in a literal delimited by [quote].
bool _needsEscape(String char, String quote) =>
    char == quote || char == r'\' || char == r'$';

/// Matches a character that would continue the name of a `$name`
/// interpolation.
final _identifierPart = RegExp('[A-Za-z0-9_]');

/// The length of the line that [joined] would take [node]'s place on.
int _joinedLineLength(AdjacentStrings node, String joined, String content) {
  final lineStart = content.lastIndexOf('\n', node.offset - 1) + 1;
  final lineEnd = switch (content.indexOf('\n', node.end)) {
    -1 => content.length,
    final end => end,
  };
  return node.offset - lineStart + joined.length + lineEnd - node.end;
}

/// A piece of a string literal: one character of its value, an escape kept
/// as written, or an interpolation.
sealed class _Piece();

/// A character of the value, such as `'` for the escape `\'`.
final class _Char(final String char) extends _Piece;

/// An escape that stays as written, such as `\n` or `\u{1F600}`.
final class _Escape(final String source) extends _Piece;

/// An interpolation, with the [name] of a `$name` one that has no braces.
final class _Interpolation(final String source, final String? name)
    extends _Piece;

/// The pieces of [string]: for a raw one, each character of its value.
List<_Piece> _piecesOf(SingleStringLiteral string, String content) =>
    switch (string) {
      SingleStringLiteral(
        isRaw: true,
        :final contentsOffset,
        :final contentsEnd,
      ) =>
        [
          for (final char
              in content.substring(contentsOffset, contentsEnd).split(''))
            _Char(char),
        ],
      SimpleStringLiteral(:final contentsOffset, :final contentsEnd) => _scan(
        content.substring(contentsOffset, contentsEnd),
      ),
      StringInterpolation(:final elements) => [
        for (final element in elements)
          ...switch (element) {
            InterpolationString(:final contentsOffset, :final contentsEnd) =>
              _scan(content.substring(contentsOffset, contentsEnd)),
            InterpolationExpression(
              :final offset,
              :final end,
              :final expression,
              rightBracket: null,
            ) =>
              [
                _Interpolation(
                  content.substring(offset, end),
                  expression.toSource(),
                ),
              ],
            InterpolationExpression(:final offset, :final end) => [
              _Interpolation(content.substring(offset, end), null),
            ],
          },
      ],
    };

/// Splits literal [text], with its escapes as written, into pieces. An
/// escaped quote, backslash or `$` is a [_Char]; other escapes are
/// [_Escape]s.
List<_Piece> _scan(String text) {
  final pieces = <_Piece>[];
  var index = 0;
  while (index < text.length) {
    if (text[index] == r'\' && index + 1 < text.length) {
      final end = _escapeEnd(text, index);
      pieces.add(switch (text[index + 1]) {
        "'" || '"' || r'\' || r'$' => _Char(text[index + 1]),
        _ => _Escape(text.substring(index, end)),
      });
      index = end;
    } else {
      pieces.add(_Char(text[index]));
      index += 1;
    }
  }
  return pieces;
}

/// The end of the escape that starts at [start] in [text]: `\xHH`, `\uHHHH`
/// and `\u{H…}` span several characters, the rest two.
int _escapeEnd(String text, int start) => switch (text[start + 1]) {
  'x' => start + 4,
  'u' when text.startsWith('{', start + 2) => text.indexOf('}', start) + 1,
  'u' => start + 6,
  _ => start + 2,
};
