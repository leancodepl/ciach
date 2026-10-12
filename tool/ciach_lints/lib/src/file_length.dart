import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';

/// Flags a file longer than [maxLines] lines. Past that a file is split along
/// a seam it already has (see the file size section of CLAUDE.md) rather than
/// grown further.
class FileLength() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  /// The most lines a file may have, counted as `wc -l` counts them.
  static const maxLines = 500;

  static const code = LintCode(
    'file_length',
    'This file is {0} lines long; keep a file under {1}.',
    correctionMessage:
        'Try splitting it along a seam: a group of tests into its own file, '
        'a helper class into its own library.',
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addCompilationUnit(this, _Visitor(this, context));
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitCompilationUnit(CompilationUnit node) {
    if (context.currentUnit case final unit?) {
      final lines = lineCount(unit.content);
      if (lines > FileLength.maxLines) {
        rule.reportAtOffset(0, 0, arguments: [lines, FileLength.maxLines]);
      }
    }
  }
}

/// The lines of [content], as `wc -l` counts them: one per line break, plus
/// an unterminated last line.
int lineCount(String content) {
  if (content.isEmpty) {
    return 0;
  }
  final breaks = '\n'.allMatches(content).length;
  return content.endsWith('\n') ? breaks : breaks + 1;
}
