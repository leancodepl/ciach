/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';
import 'package:ciach_lints/src/version_matches_pubspec.dart';

final plugin = CiachLintsPlugin();

final class CiachLintsPlugin() extends Plugin {
  @override
  String get name => 'ciach_lints';

  @override
  void register(PluginRegistry registry) {
    registry.registerWarningRule(VersionMatchesPubspec());
  }
}
