/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.join(Directory.current.path, 'example');

  test('reports only the `call` methods that no object invocation, tear-off or '
      'explicit `.call` uses', () async {
    final result = await Ciach(
      .new(
        rootPath: fixturePath,
        includeGlobs: const [
          'lib/scenarios/call_methods.dart',
          'lib/scenarios/call_methods_uses.dart',
        ],
      ),
    ).run();
    expect(result.unused.map((d) => d.qualifiedName).toSet(), {
      'NeverCalled.call',
      'OnlyCalledFromDeadCode.call',
      'callFromDeadCode',
    });
  });
}
