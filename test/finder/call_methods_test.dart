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

  Future<Set<String>> findUnused(List<String> include) async {
    final result = await Ciach(
      .new(rootPath: fixturePath, includeGlobs: include),
    ).run();
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  const expected = {
    'NeverCalled.call',
    'OnlyCalledFromDeadCode.call',
    'callFromDeadCode',
    'UnusedStaticCall.call',
  };

  test(
    'reports only the `call` methods that no object invocation, tear-off or explicit `.call` uses',
    () async {
      expect(
        await findUnused(const [
          'lib/scenarios/call_methods.dart',
          'lib/scenarios/call_methods_uses.dart',
        ]),
        expected,
      );
    },
  );

  test(
    'counts the implicit uses of a `call` method in a file that is not scanned',
    () async {
      expect(
        await findUnused(const ['lib/scenarios/call_methods.dart']),
        expected,
      );
    },
  );
}
