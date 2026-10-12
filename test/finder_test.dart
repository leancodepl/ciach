/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

@Timeout(Duration(minutes: 5))
library;

import 'package:ciach/src/models.dart';
import 'package:test/test.dart';

import 'support/finder.dart';

void main() {
  setUpFixture();

  test('reports exactly the expected unused declarations by default', () async {
    expect(await findUnused(), {
      'danglingFunction',
      '_danglingPrivate',
      'unusedConstant',
      'staleCounter',
      '_referencesOnlyInDocs',
      'UsedClass.named',
      'UsedClass.shout',
      'UsedClass.unusedMethod',
      'UsedClass._unusedField',
      'UnusedClass',
      'UnusedClass.orphanMethod',
      // A fully dead class is reported as the whole CLASS, not just its
      // constructor (which is removed with it).
      'FullyDeadClass',
      // Referenced only as a type: the class is used, only its constructor is
      // reported.
      'ReferencedAsTypeOnly.new',
      'Animal.sound',
      'Direction.south',
      'Direction.west',
      'Loud.whisper',
      'IntExtras.tripled',
      // Private constructors are reported like any other dead code. The sole,
      // zero-parameter `SoleMarker._()` also carries a prevent-instantiation
      // hint (asserted separately below).
      'SoleMarker._',
      'MultiCtor._unused',
      'ParamCtor._',
    });
  });

  test('including operators also reports operator overloads', () async {
    final unused = await findUnused(skipOperators: false);
    expect(unused, containsAll(['Vector2.+', 'Vector2.-']));
  });

  test('skips call methods by default', () async {
    final unused = await findUnused();
    // `Multiplier.call` is used via implicit-call syntax, unresolvable like an
    // operator, so skipped.
    expect(unused, isNot(contains('Multiplier.call')));
    // The rest of the fixture is genuinely used.
    expect(unused, isNot(contains('Multiplier')));
    expect(unused, isNot(contains('Multiplier.new')));
    expect(unused, isNot(contains('Multiplier.factor')));
  });

  test('reports unused private constructors like any other dead code', () async {
    final unused = await findUnused();
    // A sole, zero-parameter `Foo._()` is no longer special-cased away -> it is
    // reported as unused.
    expect(unused, contains('SoleMarker._'));
    // One of two private constructors -> genuinely dead, reported (`_used` is
    // referenced by `describe`).
    expect(unused, contains('MultiCtor._unused'));
    expect(unused, isNot(contains('MultiCtor._used')));
    // Sole private constructor that takes parameters -> also reported.
    expect(unused, contains('ParamCtor._'));
    // The classes themselves are kept alive by their static references.
    expect(unused, isNot(contains('SoleMarker')));
    expect(unused, isNot(contains('MultiCtor')));
    expect(unused, isNot(contains('ParamCtor')));
  });

  test('hints at `abstract final class` only for the sole zero-parameter '
      'prevent-instantiation constructor', () async {
    final result = await runFinder();
    UnusedDeclaration byQualified(String qualified) =>
        result.unused.firstWhere((d) => d.qualifiedName == qualified);
    // The prevent-instantiation shape (sole, zero-parameter `Foo._()`) carries
    // the hint.
    final marker = byQualified('SoleMarker._');
    expect(marker.hint, isNotNull);
    expect(marker.hint, contains('abstract final class'));
    // Removal is not blocked (no final instance fields), so it stays a normal,
    // removable finding.
    expect(marker.removalBlocked, isFalse);
    // A private constructor that is not the sole zero-parameter shape carries
    // no hint.
    expect(byQualified('MultiCtor._unused').hint, isNull);
    expect(byQualified('ParamCtor._').hint, isNull);
  });

  test('reports a declaration only mentioned in a doc comment link as '
      'doc-only, not unused', () async {
    final docOnly = await findDocOnly();
    expect(docOnly, contains('_docOnlyMentioned'));
    final unused = await findUnused();
    expect(unused, isNot(contains('_docOnlyMentioned')));
  });

  test('spans multiple files, one group per file in the report', () async {
    final result = await runFinder();
    expect(result.unused.map((d) => d.filePath).toSet(), {
      'lib/extensions.dart',
      'lib/greeting.dart',
      'lib/orphans.dart',
      'lib/private_ctors.dart',
      'lib/shapes.dart',
      'lib/user.dart',
    });
  });

  test('reports constructors without repeating the class name', () async {
    final unused = await findUnused();
    // Named constructor: `Class.ctor`, not `Class.Class.ctor`.
    expect(unused, contains('UsedClass.named'));
    expect(unused, isNot(contains('UsedClass.UsedClass.named')));
    // Unnamed constructor of a still-live class: `Class.new`.
    expect(unused, contains('ReferencedAsTypeOnly.new'));
  });

  test(
    'a fully dead class is reported as the class, not its constructor',
    () async {
      final unused = await findUnused();
      // The whole class is dead: report it once, as the class.
      expect(unused, contains('FullyDeadClass'));
      // Its unnamed constructor is not reported separately — the class removal
      // takes the constructor with it, so a stray `FullyDeadClass.new` finding
      // would be a redundant (and, on removal, build-breaking) double report.
      expect(unused, isNot(contains('FullyDeadClass.new')));
    },
  );

  test('does not flag used, entry-point, or override declarations', () async {
    final unused = await findUnused();
    // Referenced within the package, so not unused.
    expect(unused, isNot(contains('registerHandlers')));
    expect(unused, isNot(contains('_internalHelper')));
    expect(unused, isNot(contains('usedConstant')));
    expect(unused, isNot(contains('visitCount')));
    expect(unused, isNot(contains('UsedClass')));
    expect(unused, isNot(contains('UsedClass.greet')));
    expect(unused, isNot(contains('UsedClass._format')));
    expect(unused, isNot(contains('UsedClass.name')));
    expect(unused, isNot(contains('UsedClass.nickname')));
    expect(unused, isNot(contains('IntExtras.doubled')));
    expect(unused, isNot(contains('IntExtras')));
    expect(unused, isNot(contains('Loud')));
    expect(unused, isNot(contains('Loud.emphasize')));
    expect(unused, isNot(contains('Direction')));
    expect(unused, isNot(contains('Direction.north')));
    expect(unused, isNot(contains('Direction.east')));
    // Cross-file references from bin/app.dart keep these alive.
    expect(unused, isNot(contains('Animal')));
    expect(unused, isNot(contains('Dog')));
    expect(unused, isNot(contains('Dog.pace')));
    expect(unused, isNot(contains('Vector2')));
    // `main` is an entry point and is always skipped.
    expect(unused, isNot(contains('main')));
    // So is `testExecutable` in test/flutter_test_config.dart.
    expect(unused, isNot(contains('testExecutable')));
    // Skipped because it is annotated with @override.
    expect(unused, isNot(contains('Dog.sound')));
  });

  test('--no-public reports only private declarations', () async {
    expect(await findUnused(includePublic: false), {
      '_danglingPrivate',
      '_referencesOnlyInDocs',
      'UsedClass._unusedField',
      // Private constructors are private declarations, reported like any other
      // dead code.
      'SoleMarker._',
      'MultiCtor._unused',
      'ParamCtor._',
    });
  });

  test('including overrides also reports the @override method', () async {
    final unused = await findUnused(skipOverrides: false);
    expect(unused, contains('Dog.sound'));
    expect(unused, contains('Animal.sound'));
  });

  test('kind filter narrows results to the requested kinds', () async {
    expect(await findUnused(kinds: {.class$}), {
      'UnusedClass',
      'FullyDeadClass',
    });
  });

  test(
    'reports unused enum values under the enum-value kind, not enum',
    () async {
      final result = await runFinder();
      final enumValues = {
        for (final d in result.unused)
          if (d.kind == .enumMember) d.qualifiedName,
      };
      expect(enumValues, {'Direction.south', 'Direction.west'});
      final enumTypes = {
        for (final d in result.unused)
          if (d.kind == .enum$) d.qualifiedName,
      };
      expect(enumTypes, isNot(contains('Direction.south')));
      expect(enumTypes, isNot(contains('Direction.west')));
    },
  );

  test(
    'enum-value kind filter selects unused enum values, enum does not',
    () async {
      expect(await findUnused(kinds: {.enumMember}), {
        'Direction.south',
        'Direction.west',
      });
      // `-k enum` no longer picks them up; the fixture has no unused enum type.
      expect(await findUnused(kinds: {.enum$}), isEmpty);
    },
  );

  test('exclude globs remove files from the scan', () async {
    // Excluding lib leaves only bin/app.dart, whose only declaration is the
    // skipped `main`, so nothing is reported.
    expect(await findUnused(exclude: ['lib/**']), isEmpty);
  });

  test('a reference from inside its own span keeps nothing alive', () async {
    // `_countdown` and `Walker._depth` only call themselves, and `Chain` is
    // named only by its own field. `factorial` and `Walker._step` call
    // themselves as well, but something else calls them, so they stay.
    expect(
      await findUnused(
        include: ['lib/scenarios/self_references.dart'],
        exclude: const [],
      ),
      {'_countdown', 'Walker._depth', 'Chain', 'Chain.next'},
    );
  });
}
