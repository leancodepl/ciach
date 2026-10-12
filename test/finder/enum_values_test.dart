@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('enum `.values` detection fix', () {
    // Scan only the enum-`.values` fixture (enums kept alive by in-file refs).
    Future<FinderResult> runEnumValues() =>
        runScenario(['lib/scenarios/enum_values.dart']);

    test(
      'enum values reached only via qualified `EnumName.values` iteration are '
      'never flagged',
      () async {
        final names = qualifiedNames((await runEnumValues()).unused);
        // All three values are reachable through `IterableColor.values`.
        expect(names, isNot(contains('IterableColor.red')));
        expect(names, isNot(contains('IterableColor.green')));
        expect(names, isNot(contains('IterableColor.blue')));
        // The enum type itself is used (via `.values`) and never flagged.
        expect(names, isNot(contains('IterableColor')));
      },
    );

    test(
      'enum values reached via the implicit (bare) `values` getter inside the '
      'enum body are never flagged',
      () async {
        final result = await runEnumValues();
        final names = qualifiedNames(result.unused);
        expect(names, isNot(contains('SelfIteratingUnit.first')));
        expect(names, isNot(contains('SelfIteratingUnit.second')));
        // The values are genuinely absent from the report, not merely present.
        final ofEnum = result.unused
            .where((d) => d.container == 'SelfIteratingUnit' && d.isEnumValue)
            .toList();
        expect(ofEnum, isEmpty);
      },
    );
  });
}
