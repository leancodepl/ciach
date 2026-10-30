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
  test(
    "`@pragma('vm:entry-point')` keeps the declaration and the class that declares it, and no other annotation does",
    () async {
      final result = await Ciach(
        .new(
          rootPath: p.join(Directory.current.path, 'example'),
          includeGlobs: const ['lib/scenarios/vm_entry_points.dart'],
        ),
      ).run();

      expect(result.unused.map((d) => d.qualifiedName), {
        'Host.helper',
        'inlined',
        'deprecatedMention',
      });
    },
  );
}
