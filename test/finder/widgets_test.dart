@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('dead widget classes', () {
    // The live widget is constructed in bin/app.dart.
    Future<FinderResult> runWidgets() =>
        runScenario(['lib/scenarios/widgets.dart']);

    test(
      'reports a fully dead StatefulWidget as a class and couples its State',
      () async {
        final result = await runWidgets();
        final names = qualifiedNames(result.unused);
        // The widget class itself is reported (its only references are its own
        // constructor and the `State<DeadStatefulWidget>` pairing)...
        expect(names, contains('DeadStatefulWidget'));
        // ...but not its constructor, and not the paired private State subclass,
        // which is not independently "unused" (createState references it).
        expect(names, isNot(contains('DeadStatefulWidget.new')));
        expect(names, isNot(contains('_DeadStatefulWidgetState')));
        // The State subclass is instead coupled to the widget's removal, so
        // `--remove` deletes both and never leaves `State<DeadStatefulWidget>`
        // referring to a deleted type.
        final widget = result.unused.firstWhere(
          (d) => d.name == 'DeadStatefulWidget',
        );
        expect(widget.kind, SymbolKind.class$);
        expect(widget.coupledRemovals, isNotEmpty);
      },
    );

    for (final transitive in [false, true]) {
      test('a dead widget whose State is used elsewhere is report-only '
          '(transitive: $transitive)', () async {
        final result = await runScenario([
          'lib/scenarios/widgets.dart',
        ], transitive: transitive);
        final widget = findByQualified(result, 'KeyedWidget')!;
        expect(widget.removalBlocked, isTrue);
        expect(widget.coupledRemovals, isEmpty);
        expect(findByQualified(result, '_KeyedWidgetState'), isNull);
      });
    }

    test('couples a State declared in another file', () async {
      final result = await runScenario([
        'lib/scenarios/widgets.dart',
        'lib/scenarios/widgets_state.dart',
      ]);
      final widget = findByQualified(result, 'SplitWidget')!;
      expect(widget.removalBlocked, isFalse);
      expect(widget.coupledRemovals.map((c) => c.filePath), [
        'lib/scenarios/widgets_state.dart',
      ]);
      expect(findByQualified(result, 'SplitWidgetState'), isNull);
    });

    test(
      'blocks a widget whose State in another file is not scanned',
      () async {
        final result = await runWidgets();
        final widget = findByQualified(result, 'SplitWidget')!;
        expect(widget.removalBlocked, isTrue);
        expect(widget.coupledRemovals, isEmpty);
      },
    );

    test(
      'never flags a live widget-style class or the State stand-in',
      () async {
        final names = qualifiedNames((await runWidgets()).unused);
        // Constructed from bin/app.dart -> a real external use.
        expect(names, isNot(contains('LiveWidget')));
        // Used as the supertype of the paired State subclasses.
        expect(names, isNot(contains('State')));
      },
    );
  });
}
