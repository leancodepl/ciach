@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('conditional imports', () {
    Set<String> unusedIn(FinderResult result) => {
      for (final d in result.unused)
        if (d.filePath != 'lib/scenarios/conditional/conditional_uses.dart')
          '${p.basename(d.filePath)}:${d.qualifiedName}',
    };

    test('namesakes in the variants share their references', () async {
      final result = await runScenario(const ['lib/scenarios/conditional/**']);

      expect(unusedIn(result), {
        'platform_io.dart:conditionalDeadOnBoth',
        'platform_web.dart:conditionalDeadOnBoth',
        'platform_web.dart:conditionalWebOnly',
        'platform_web.dart:ConditionalPlatform._unusedWebOnly',
        'platform_web.dart:extension on String',
        'unrelated.dart:conditionalIsWeb',
        'web_label.dart:deadWebLabel',
      });
    });

    test('a declaration whose namesake is not read is not checked', () async {
      final result = await runScenario(const [
        'lib/scenarios/conditional/platform_web.dart',
        'lib/scenarios/conditional/web_label.dart',
      ]);

      expect(unusedIn(result), {
        'platform_web.dart:ConditionalPlatform._unusedWebOnly',
        'platform_web.dart:extension on String',
        'web_label.dart:deadWebLabel',
      });
    });
  });
}
