/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/ciach.dart';
import 'package:test/test.dart';

import '../support/test_package.dart';

void main() {
  test(
    'a second run of the same finder reports what the first reported',
    () async {
      final package = TestPackage('repeated_run')
        ..writeAll({
          'pubspec.yaml': 'name: app\n',
          'lib/a.dart': '''
void unused() {}

int? _empty;
''',
        });
      addTearDown(package.dispose);
      final ciach = Ciach(.new(rootPath: package.root));

      final first = await ciach.run();
      final second = await ciach.run();

      expect(
        [
          for (final result in [first, second])
            result.unused.map((declaration) => declaration.qualifiedName),
        ],
        [
          ['unused', '_empty'],
          ['unused', '_empty'],
        ],
      );
    },
  );
}
