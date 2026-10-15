/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:ciach_lints/src/avoid_empty_collection_fallback.dart';
import 'package:ciach_lints/src/merge_identical_switch_arms.dart';
import 'package:ciach_lints/src/prefer_let.dart';
import 'package:ciach_lints/src/prefer_multiline_string.dart';
import 'package:ciach_lints/src/prefer_none_and_where_not.dart';
import 'package:ciach_lints/src/prefer_pattern_over_guard.dart';
import 'package:ciach_lints/src/prefer_single_string_literal.dart';
import 'package:ciach_lints/src/version_matches_pubspec.dart';

final plugin = CiachLintsPlugin();

final class CiachLintsPlugin() extends Plugin {
  @override
  String get name => 'ciach_lints';

  @override
  void register(PluginRegistry registry) {
    registry
      ..registerWarningRule(PreferLet())
      ..registerFixForRule(PreferLet.code, ReplaceWithLet.new)
      ..registerWarningRule(VersionMatchesPubspec())
      ..registerFixForRule(
        VersionMatchesPubspec.code,
        UpdateConstantVersion.new,
      )
      ..registerFixForRule(VersionMatchesPubspec.code, UpdatePubspecVersion.new)
      ..registerWarningRule(PreferMultilineString())
      ..registerFixForRule(
        PreferMultilineString.code,
        ConvertToMultilineString.new,
      )
      ..registerWarningRule(PreferSingleStringLiteral())
      ..registerFixForRule(
        PreferSingleStringLiteral.code,
        JoinAdjacentStrings.new,
      )
      ..registerWarningRule(AvoidEmptyCollectionFallback())
      ..registerFixForRule(
        AvoidEmptyCollectionFallback.code,
        SkipNullCollection.new,
      )
      ..registerWarningRule(PreferPatternOverGuard())
      ..registerFixForRule(
        PreferPatternOverGuard.code,
        MoveGuardIntoPattern.new,
      )
      ..registerWarningRule(PreferNoneAndWhereNot())
      ..registerFixForRule(PreferNoneAndWhereNot.code, RemoveNegation.new)
      ..registerWarningRule(MergeIdenticalSwitchArms())
      ..registerFixForRule(MergeIdenticalSwitchArms.code, MergeSwitchArms.new);
  }
}
