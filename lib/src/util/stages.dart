/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Named steps of a run, which [recordStages] records as a tree. Outside
/// [recordStages], [stage] only calls its body.
library;

import 'dart:async';

/// A step that ran, with the steps that ran inside it, in the order in which
/// they started.
final class Stage {
  /// Creates a stage named [name] that has no steps inside it yet.
  Stage(this.name);

  /// What the step does, such as `Collect declarations`.
  final String name;

  final List<Stage> children = [];
}

/// The zone value that holds the [Stage] that the current code runs in.
const _currentStage = #ciach.stage;

/// Runs [body] as the stage [name], inside the stage that the caller runs in.
///
/// The stage holds everything that [body] starts, also after an `await`.
T stage<T>(String name, T Function() body) {
  if (Zone.current[_currentStage] case final Stage parent) {
    final child = Stage(name);
    parent.children.add(child);
    return runZoned(body, zoneValues: {_currentStage: child});
  }
  return body();
}

/// Runs [body] and returns the stages that it ran, in the order in which they
/// started.
Future<List<Stage>> recordStages(Future<void> Function() body) async {
  final root = Stage('');
  await runZoned(body, zoneValues: {_currentStage: root});
  return root.children;
}
