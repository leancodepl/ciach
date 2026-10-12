@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:test/test.dart';

import '../support/finder.dart';

void main() {
  setUpFixture();

  group('dot-shorthand references', () {
    // Each declaration below is reached from lib/dot_shorthand_uses.dart only
    // through a `.name` shorthand, one per context Dart allows a shorthand in,
    // so a context the reference search cannot see surfaces as exactly one
    // finding here.
    const shorthandReached = {
      // Argument positions.
      'Weight.positional',
      'Weight.named',
      // Initializers, returns, and yields.
      'Weight.variableInit',
      'Weight.fieldInit',
      'Weight.arrowReturn',
      'Weight.blockReturn',
      'Weight.asyncReturn',
      'Weight.yielded',
      // Collection, record, and map literals.
      'Weight.listElement',
      'Weight.setElement',
      'Weight.mapKey',
      'Weight.mapValue',
      'Weight.recordField',
      // Patterns.
      'Weight.switchCase',
      'Weight.switchArm',
      'Weight.ifCase',
      'Palette.patternField',
      // Operators and conditionals.
      'Weight.equality',
      'Weight.ternaryThen',
      'Weight.ternaryElse',
      'Weight.ifNull',
      // Constant contexts.
      'Weight.paramDefault',
      'Weight.constArg',
      'Weight.annotationArg',
      // Assignment, and a context type from an inferred type argument.
      'Weight.assignment',
      'Weight.typeArgument',
      // A shorthand inside the declaring library.
      'Weight.sameFile',
      // Shorthand heads other than an enum value: constructors, statics on a
      // class and on an enum, a generic static, nesting, and trailing
      // selectors.
      'Palette.new',
      'Palette.of',
      'Palette.constField',
      'Palette.getter',
      'Palette.parse',
      'Palette.blend',
      'Palette.nestedFirst',
      'Palette.nestedSecond',
      'Palette.chainSeed',
      'Palette.cascadeSeed',
      'Palette.tinted',
      'Tier.standard',
      'Box.filled',
      // Nested constructor shorthands: the three unnamed heads of a
      // `.new(.new(.new(…)))` chain, outermost first, and a named constructor
      // nested in a static-method shorthand.
      'Layer.new',
      'Depth.new',
      'Tint.new',
      'Tint.step',
    };

    Future<FinderResult> runShorthandsResult() => runScenario(const [
      'lib/scenarios/dot_shorthands.dart',
      'lib/scenarios/dot_shorthand_uses.dart',
    ]);

    Future<Set<String>> runShorthands() async => (await runShorthandsResult())
        .unused
        .map((d) => d.qualifiedName)
        .toSet();

    test('no declaration reached only through a dot shorthand is reported, in '
        'any context a shorthand is allowed in', () async {
      final result = await runShorthandsResult();
      // Doc-only counts as a miss too: a shorthand the reference search cannot
      // see must not be papered over by a dartdoc mention.
      final reported = {
        for (final d in [...result.unused, ...result.docOnly]) d.qualifiedName,
      };
      // Compared as a set so a failure lists exactly which shorthand context
      // went unseen.
      expect(reported.intersection(shorthandReached), isEmpty);
    });

    test('the shorthand fixture reports exactly its dead controls — the '
        'detection is real, not a blanket exemption', () async {
      expect(await runShorthands(), {
        // Same shapes as the shorthand-reached declarations above, but no
        // shorthand (and no other reference) reaches them.
        'Weight.deadWeight',
        'Tier.deadStandard',
        'Palette.deadCtor',
        'Palette.deadGetter',
        'Palette.deadParse',
        'Box.deadFilled',
        // Constructing a class through one shorthand does not exempt its other
        // constructors…
        'Tint.deadTint',
        // …and an unnamed constructor no shorthand ever reaches is still
        // reported, even though `.new` sites are now probed by name.
        'DeadLayer.new',
        // The fixture's own entry point, which nothing calls.
        'exerciseDotShorthands',
      });
    });
  });
}
