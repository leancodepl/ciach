/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/analysis_rule/analysis_rule.dart';
import 'package:analyzer/analysis_rule/rule_context.dart';
import 'package:analyzer/analysis_rule/rule_visitor_registry.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:yaml/yaml.dart';

/// Flags a `ciachVersion` constant whose value differs from the `version` in
/// the package's `pubspec.yaml`, so `--version` never reports a stale number.
class VersionMatchesPubspec() extends AnalysisRule {
  this : super(name: code.lowerCaseName, description: code.problemMessage);

  static const code = LintCode(
    'version_matches_pubspec',
    "'ciachVersion' is '{0}', but pubspec.yaml says '{1}'.",
    correctionMessage:
        "Try updating 'ciachVersion' or the pubspec version so they match.",
    severity: .WARNING,
  );

  @override
  LintCode get diagnosticCode => code;

  @override
  void registerNodeProcessors(
    RuleVisitorRegistry registry,
    RuleContext context,
  ) {
    registry.addTopLevelVariableDeclaration(this, _Visitor(this, context));
  }
}

class _Visitor(final AnalysisRule rule, final RuleContext context)
    extends SimpleAstVisitor<void> {
  @override
  void visitTopLevelVariableDeclaration(TopLevelVariableDeclaration node) {
    for (final variable in node.variables.variables) {
      if (variable case VariableDeclaration(
        name: Token(lexeme: 'ciachVersion'),
        initializer: SimpleStringLiteral(:final value) && final literal,
      )) {
        if (_pubspecVersion case final pubspecVersion?
            when pubspecVersion != value) {
          rule.reportAtNode(literal, arguments: [value, pubspecVersion]);
        }
      }
    }
  }

  /// The `version` of the package owning the analyzed file, or `null` when
  /// there is no readable pubspec or it declares no version.
  String? get _pubspecVersion {
    final pubspec = context.package?.root.getFile('pubspec.yaml');
    if (pubspec == null || !pubspec.exists) {
      return null;
    }
    try {
      return switch (loadYaml(pubspec.readAsStringSync())) {
        {'version': final String version} => version,
        _ => null,
      };
    } on YamlException {
      return null;
    }
  }
}
