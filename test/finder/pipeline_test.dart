/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Golden test for `doc/pipeline.md`: scans `example/` once per entry of
/// [runs], records the stages of each scan and compares the flowchart that
/// they make with the committed file. So the diagram can't drift from the
/// stages in the code.
///
///     dart test test/finder/pipeline_test.dart                    # compare
///     UPDATE_GOLDENS=1 dart test test/finder/pipeline_test.dart   # rewrite
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/util/stages.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/pipeline_diagram.dart';

final updateGoldens = Platform.environment['UPDATE_GOLDENS'] == '1';

final examplePath = p.join(Directory.current.path, 'example');

/// The scans that the diagram is drawn from, by the options that they set,
/// the default scan first. Together they run every stage.
final runs = <String, FinderOptions>{
  'defaults': .new(rootPath: examplePath),
  '--no-transitive': .new(rootPath: examplePath, transitive: false),
  '--exported-packages=.': .new(
    rootPath: examplePath,
    exportedPackages: const ['.'],
  ),
};

String pipelineDoc(String flowchart) =>
    '''
<!-- Written by test/finder/pipeline_test.dart; rewrite it with
     `UPDATE_GOLDENS=1 dart test test/finder/pipeline_test.dart`. -->

# How a scan runs

Each box is a step of a scan, and a box that holds other boxes runs them in
order. The diagram is drawn from scans of `example/`, so it shows the steps
that `lib/src/finder.dart` and `lib/src/settle/settler.dart` mark with
`stage(…)`. A note under a step names the options that it depends on.

```mermaid
$flowchart
```
''';

void main() {
  test(
    '`doc/pipeline.md` shows the stages that scans of `example/` run',
    () async {
      final stagesByRun = {
        for (final MapEntry(key: run, value: options) in runs.entries)
          run: await recordStages(() => Ciach(options).run()),
      };
      final doc = pipelineDoc(
        mermaidFlowchart(mergeRuns(stagesByRun), runs.keys.toList()),
      );

      final file = File('doc/pipeline.md');
      if (updateGoldens) {
        file.writeAsStringSync(doc);
        printOnFailure('Rewrote ${file.path}');
        return;
      }
      expect(
        file.readAsStringSync(),
        doc,
        reason:
            '${file.path} differs from the stages that the scans ran. If the '
            'change is intended, run '
            '`UPDATE_GOLDENS=1 dart test test/finder/pipeline_test.dart` and '
            'commit the result.',
      );
    },
  );
}
