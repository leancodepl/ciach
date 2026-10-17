/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/util/stages.dart';
import 'package:test/test.dart';

/// The names of [stages]. A stage that holds other stages is a map from its
/// name to their names.
Object names(List<Stage> stages) => [
  for (final Stage(:name, :children) in stages)
    if (children.isEmpty) name else {name: names(children)},
];

void main() {
  test('`stage` outside `recordStages` returns what its body returns', () {
    expect(stage('a', () => 1), 1);
  });

  test('`recordStages` nests a stage started after an `await` in the stage '
      'that awaited', () async {
    final stages = await recordStages(() async {
      await stage('outer', () async {
        await Future<void>.delayed(Duration.zero);
        stage('inner', () {});
      });
      stage('next', () {});
    });

    expect(names(stages), [
      {
        'outer': ['inner'],
      },
      'next',
    ]);
  });

  test('`recordStages` lists concurrent stages in the order in which they '
      'started', () async {
    final stages = await recordStages(
      () => Future.wait([
        stage('slow', () => Future<void>.delayed(const .new(milliseconds: 5))),
        stage('fast', Future<void>.value),
      ]),
    );

    expect(names(stages), ['slow', 'fast']);
  });
}
