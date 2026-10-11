/*
 * AI-Provenance:
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

/// Flags a single-line string literal with two or more interior `\n` escapes:
/// text with that many line breaks is what `CLAUDE.md` asks to be written as a
/// `'''` multi-line string, where the breaks are real.
///
/// A newline is interior when it is not the last character of the string, so
/// `'line\n'`, `'a\nb'` and `'\n\n'` all pass. One interior newline is allowed
/// because such a string is usually a reason message or a two-line fixture,
/// which reads fine inline. The escapes are counted across every literal part
/// of an interpolated string. Raw strings and existing multi-line strings are
/// never flagged.
class PreferMultilineString() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'prefer_multiline_string',
    r"This string has {0} interior '\n' escapes.",
    correctionMessage: "Try rewriting it as a ''' multi-line string.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    final visitor = _Visitor(this, context);
    registry
      ..addSimpleStringLiteral(this, visitor)
      ..addStringInterpolation(this, visitor);
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitSimpleStringLiteral(SimpleStringLiteral node) => _check(node);

  @override
  void visitStringInterpolation(StringInterpolation node) => _check(node);

  void _check(SingleStringLiteral node) {
    if (node.isRaw || node.isMultiline) {
      return;
    }
    if (context.currentUnit case final unit?) {
      final newlines = _interiorNewlines(_piecesOf(node, unit.content));
      if (newlines >= 2) {
        rule.reportAtNode(node, arguments: [newlines]);
      }
    }
  }
}

/// Rewrites the literal flagged by [PreferMultilineString] as a `'''` string
/// (or a `"""` one when the text contains `'''`): the opening quotes are
/// followed by a newline, each `\n` escape becomes a line break, quote
/// escapes go, and everything else, interpolations included, stays as it is.
class ConvertToMultilineString({required super.context})
    extends ResolvedCorrectionProducer {
  @override
  CorrectionApplicability get applicability => .automatically;

  @override
  FixKind get fixKind => const .new(
    'ciach_lints.fix.convertToMultilineString',
    DartFixKindPriority.standard,
    'Convert to a multi-line string',
  );

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if (node
        case SingleStringLiteral(isRaw: false, isMultiline: false) &&
            final literal) {
      final pieces = _piecesOf(literal, unitResult.content);
      if (_multilineForm(pieces) case final replacement?) {
        await builder.addDartFileEdit(
          file,
          (builder) =>
              builder.addSimpleReplacement(range.node(literal), replacement),
        );
      }
    }
  }
}

/// A piece of a single-line string literal's source.
sealed class _Piece();

/// A `\n` escape.
final class _Newline() extends _Piece;

/// An escaped quote, which a multi-line string spells without the backslash.
final class _Quote(final String quote) extends _Piece;

/// Source that a multi-line string keeps as it is: plain characters, other
/// escapes and interpolations.
final class _Verbatim(final String source) extends _Piece;

/// The pieces of [literal], read from [content], the text of its file.
List<_Piece> _piecesOf(SingleStringLiteral literal, String content) =>
    switch (literal) {
      SimpleStringLiteral(:final contentsOffset, :final contentsEnd) => _scan(
        content.substring(contentsOffset, contentsEnd),
      ),
      StringInterpolation(:final elements) => [
        for (final element in elements)
          ...switch (element) {
            InterpolationString(:final contentsOffset, :final contentsEnd) =>
              _scan(content.substring(contentsOffset, contentsEnd)),
            InterpolationExpression(:final offset, :final end) => [
              _Verbatim(content.substring(offset, end)),
            ],
          },
      ],
    };

/// Splits literal [text], escapes still in source form, into pieces.
List<_Piece> _scan(String text) {
  final pieces = <_Piece>[];
  var index = 0;
  while (index < text.length) {
    if (text[index] == r'\' && index + 1 < text.length) {
      final escaped = text[index + 1];
      pieces.add(switch (escaped) {
        'n' => _Newline(),
        "'" || '"' => _Quote(escaped),
        _ => _Verbatim(text.substring(index, index + 2)),
      });
      index += 2;
    } else {
      pieces.add(_Verbatim(text[index]));
      index += 1;
    }
  }
  return pieces;
}

/// Counts the `\n` escapes in [pieces] other than one ending the string.
int _interiorNewlines(List<_Piece> pieces) {
  final newlines = pieces.whereType<_Newline>().length;
  return pieces.lastOrNull is _Newline ? newlines - 1 : newlines;
}

/// The multi-line form of [pieces], or null when none is clean: a line of the
/// result would end in whitespace, or the text cannot sit between `'''` or
/// `"""` quotes without escapes.
String? _multilineForm(List<_Piece> pieces) {
  final text = pieces
      .map(
        (piece) => switch (piece) {
          _Newline() => '\n',
          _Quote(:final quote) => quote,
          _Verbatim(:final source) => source,
        },
      )
      .join();
  final quotes = ["'''", '"""']
      .where((quotes) => !text.contains(quotes) && !text.endsWith(quotes[0]))
      .firstOrNull;
  if (quotes == null) {
    return null;
  }
  final result = '$quotes\n$text$quotes';
  final hasTrailingWhitespace = result
      .split('\n')
      .any((line) => line.endsWith(' ') || line.endsWith('\t'));
  return hasTrailingWhitespace ? null : result;
}
