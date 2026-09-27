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
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/error/error.dart';
import 'package:analyzer_plugin/utilities/change_builder/change_builder_core.dart';
import 'package:analyzer_plugin/utilities/fixes/fixes.dart';
import 'package:analyzer_plugin/utilities/range_factory.dart';
import 'package:ciach_lints/src/pubspec_version.dart';

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
        if (readPubspecVersion(context.package) case final pubspec?
            when pubspec.value != value) {
          rule.reportAtNode(literal, arguments: [value, pubspec.value]);
        }
      }
    }
  }
}

/// A fix for [VersionMatchesPubspec], applied at the flagged `ciachVersion`
/// literal.
sealed class _AlignVersions({required super.context})
    extends ResolvedCorrectionProducer {
  late final _pubspecVersion = readPubspecVersion(
    unitResult.session.analysisContext.contextRoot.workspace.findPackageFor(
      file,
    ),
  );

  String? get _constantVersion => switch (node) {
    SimpleStringLiteral(:final value) => value,
    _ => null,
  };

  // The two fixes pull in opposite directions, so neither may run unasked.
  @override
  CorrectionApplicability get applicability => .singleLocation;
}

/// Sets `ciachVersion` to the pubspec version.
class UpdateConstantVersion({required super.context}) extends _AlignVersions {
  @override
  FixKind get fixKind => const .new(
    'ciach_lints.fix.updateConstantVersion',
    DartFixKindPriority.standard,
    "Update 'ciachVersion' to '{0}'",
  );

  @override
  List<String> get fixArguments => [?_pubspecVersion?.value];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if ((node, _pubspecVersion) case (
      final SimpleStringLiteral literal,
      final pubspec?,
    )) {
      await builder.addDartFileEdit(
        file,
        (builder) => builder.addSimpleReplacement(
          range.startOffsetEndOffset(
            literal.contentsOffset,
            literal.contentsEnd,
          ),
          pubspec.value,
        ),
      );
    }
  }
}

/// Sets the pubspec version to `ciachVersion`.
class UpdatePubspecVersion({required super.context}) extends _AlignVersions {
  @override
  FixKind get fixKind => const .new(
    'ciach_lints.fix.updatePubspecVersion',
    DartFixKindPriority.standard,
    "Update the pubspec version to '{0}'",
  );

  @override
  List<String> get fixArguments => [?_constantVersion];

  @override
  Future<void> compute(ChangeBuilder builder) async {
    if ((_constantVersion, _pubspecVersion) case (
      final version?,
      final pubspec?,
    )) {
      await builder.addYamlFileEdit(
        pubspec.path,
        (builder) => builder.addSimpleReplacement(pubspec.range, version),
      );
    }
  }
}
