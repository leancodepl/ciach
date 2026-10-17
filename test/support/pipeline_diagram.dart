/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Draws the stages that several runs recorded as one Mermaid flowchart, for
/// `doc/pipeline.md`.
library;

import 'package:ciach/src/util/stages.dart';
import 'package:collection/collection.dart';

/// A stage as it ran in any of several runs.
final class MergedStage {
  MergedStage(this.name);

  final String name;

  /// The names of the runs in which the stage ran.
  final Set<String> runs = {};

  /// Whether a run ran the stage several times in a row, such as the rounds
  /// of `--transitive`.
  bool repeats = false;

  final List<MergedStage> children = [];
}

/// Returns the stages of every run in [stagesByRun], merged by name.
///
/// A stage keeps its place among the stages next to it: when the first run
/// ran `A`, `C` and the second ran `A`, `B`, `C`, the result is `A`, `B`, `C`.
List<MergedStage> mergeRuns(Map<String, List<Stage>> stagesByRun) {
  final merged = <MergedStage>[];
  for (final MapEntry(key: run, value: stages) in stagesByRun.entries) {
    _mergeInto(merged, stages, run);
  }
  return merged;
}

void _mergeInto(List<MergedStage> merged, List<Stage> stages, String run) {
  var next = 0;
  for (final repeats in _consecutiveRepeats(stages)) {
    final name = repeats.first.name;
    final found = merged.indexWhere((m) => m.name == name);
    final MergedStage target;
    if (found == -1) {
      target = MergedStage(name);
      merged.insert(next, target);
      next++;
    } else {
      target = merged[found];
      next = found + 1;
    }
    target.runs.add(run);
    target.repeats = target.repeats || repeats.length > 1;
    for (final stage in repeats) {
      _mergeInto(target.children, stage.children, run);
    }
  }
}

/// Groups [stages] into runs of stages with the same name, one after
/// another: `A`, `A`, `B` gives `[A, A]`, `[B]`.
Iterable<List<Stage>> _consecutiveRepeats(List<Stage> stages) sync* {
  var group = <Stage>[];
  for (final stage in stages) {
    if (group.isNotEmpty && group.first.name != stage.name) {
      yield group;
      group = [];
    }
    group.add(stage);
  }
  if (group.isNotEmpty) {
    yield group;
  }
}

/// Returns a Mermaid flowchart of [stages], which ran in [runs].
///
/// The first of [runs] is the default run. A stage that it skipped is marked
/// with the runs that ran it, and a stage that it ran is marked with the runs
/// that skipped it. A stage that ran in the same runs as the stage around it
/// isn't marked.
String mermaidFlowchart(List<MergedStage> stages, List<String> runs) => [
  'flowchart TD',
  ..._flowchartLines(stages, runs, runs.toSet(), 's', '  '),
].join('\n');

Iterable<String> _flowchartLines(
  List<MergedStage> stages,
  List<String> runs,
  Set<String> outerRuns,
  String idPrefix,
  String indent,
) sync* {
  final ids = [for (final (i, _) in stages.indexed) '$idPrefix$i'];
  for (final (i, stage) in stages.indexed) {
    final label = _label(stage, runs, outerRuns);
    if (stage.children.isEmpty) {
      yield '$indent${ids[i]}["$label"]';
    } else {
      yield '${indent}subgraph ${ids[i]} ["$label"]';
      yield* _flowchartLines(
        stage.children,
        runs,
        stage.runs,
        '${ids[i]}_',
        '$indent  ',
      );
      yield '${indent}end';
    }
  }
  if (ids.length > 1) {
    yield '$indent${ids.join(' --> ')}';
  }
}

String _label(MergedStage stage, List<String> runs, Set<String> outerRuns) {
  // Every second part of a name split at backticks is code.
  final name = [
    for (final (i, part) in stage.name.split('`').indexed)
      if (i.isOdd) _code(part) else part,
  ].join();
  final skippedBy = runs.where((run) => !stage.runs.contains(run)).toList();
  final notes = [
    if (const SetEquality<String>().equals(stage.runs, outerRuns))
      null
    else if (!stage.runs.contains(runs.first))
      'only with ${stage.runs.map(_code).join(', ')}'
    else if (skippedBy.isNotEmpty)
      'skipped with ${skippedBy.map(_code).join(', ')}',
    if (stage.repeats) 'repeats',
  ].nonNulls;
  return [name, for (final note in notes) '<i>$note</i>'].join('<br/>');
}

String _code(String text) => '<code>$text</code>';
