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

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/models.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:test/test.dart';

void main() {
  // The example package doubles as the test fixture: a real `sample_pkg`
  // package with a known mix of used and unused declarations.
  final fixturePath = p.join(Directory.current.path, 'example');

  setUpAll(() async {
    // The fixture is a real package; the analysis server needs its
    // package_config.json to resolve `package:sample_pkg/...` imports.
    final config = File(
      p.join(fixturePath, '.dart_tool', 'package_config.json'),
    );
    if (!config.existsSync()) {
      final result = await Process.run(Platform.resolvedExecutable, [
        'pub',
        'get',
      ], workingDirectory: fixturePath);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    }
  });

  Future<FinderResult> runFinder({
    bool includePublic = true,
    bool skipOverrides = true,
    bool skipOperators = true,
    Set<SymbolKind>? kinds,
    // The widget/union/guard fixtures are scanned only by their dedicated
    // tests; exclude them from the default-run assertions.
    List<String> exclude = const [
      'lib/widgets.dart',
      'lib/unions.dart',
      'lib/guards.dart',
    ],
    List<String> include = const [],
  }) => Ciach(
    .new(
      rootPath: fixturePath,
      includePublic: includePublic,
      skipOverrides: skipOverrides,
      skipOperators: skipOperators,
      kinds: kinds ?? FinderOptions.defaultKinds,
      excludeGlobs: exclude,
      includeGlobs: include,
    ),
  ).run();

  Future<Set<String>> findUnused({
    bool includePublic = true,
    bool skipOverrides = true,
    bool skipOperators = true,
    Set<SymbolKind>? kinds,
    List<String> exclude = const [
      'lib/widgets.dart',
      'lib/unions.dart',
      'lib/guards.dart',
    ],
    List<String> include = const [],
  }) async {
    final result = await runFinder(
      includePublic: includePublic,
      skipOverrides: skipOverrides,
      skipOperators: skipOperators,
      kinds: kinds,
      exclude: exclude,
      include: include,
    );
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  Future<Set<String>> findDocOnly({bool includePublic = true}) async {
    final result = await runFinder(includePublic: includePublic);
    return result.docOnly.map((d) => d.qualifiedName).toSet();
  }

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
      'tripled',
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
    expect(unused, isNot(contains('doubled')));
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

  test('exclude globs remove files from the scan', () async {
    // Excluding lib leaves only bin/app.dart, whose only declaration is the
    // skipped `main`, so nothing is reported.
    expect(await findUnused(exclude: ['lib/**']), isEmpty);
  });

  group('dead widget classes', () {
    // Scan only the widget fixture; cross-package references (e.g. the live
    // widget constructed in bin/app.dart) still resolve, since the analysis
    // server analyses the whole package regardless of the candidate filter.
    Future<FinderResult> runWidgets() =>
        runFinder(include: ['lib/widgets.dart'], exclude: const []);

    test(
      'reports a fully dead StatelessWidget-style class as a class',
      () async {
        final result = await runWidgets();
        final names = result.unused.map((d) => d.qualifiedName).toSet();
        // The whole class is dead — reported once, as the class, not just its
        // constructor.
        expect(names, contains('DeadLeafWidget'));
        expect(names, isNot(contains('DeadLeafWidget.new')));
        final leaf = result.unused.firstWhere(
          (d) => d.name == 'DeadLeafWidget',
        );
        expect(leaf.kind, SymbolKind.class$);
      },
    );

    test(
      'reports a fully dead StatefulWidget as a class and couples its State',
      () async {
        final result = await runWidgets();
        final names = result.unused.map((d) => d.qualifiedName).toSet();
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

    test(
      'never flags a live widget-style class or the State stand-in',
      () async {
        final names = (await runWidgets()).unused
            .map((d) => d.qualifiedName)
            .toSet();
        // Constructed from bin/app.dart -> a real external use.
        expect(names, isNot(contains('LiveWidget')));
        // Used as the supertype of the paired State subclasses.
        expect(names, isNot(contains('State')));
      },
    );
  });

  group('unused union members (opt-in --unused-union-members)', () {
    // Scan only the union fixture; cross-file references (the live member
    // constructed in bin/app.dart) still resolve, since the analysis server
    // analyses the whole package regardless of the candidate filter.
    Future<FinderResult> runUnions({required bool flag}) => Ciach(
      .new(
        rootPath: fixturePath,
        unusedUnionMembers: flag,
        includeGlobs: const ['lib/unions.dart'],
      ),
    ).run();

    UnusedDeclaration? findByName(FinderResult result, String name) {
      for (final decl in result.unused) {
        if (decl.name == name) {
          return decl;
        }
      }
      return null;
    }

    test(
      'flag ON: a member matched only by a switch-statement case is '
      'reported but report-only (removal blocked, no coupled arms)',
      () async {
        final result = await runUnions(flag: true);
        final decl = findByName(result, 'StatementOnlySignal');
        expect(decl, isNotNull, reason: 'should be flagged dead');
        expect(decl!.kind, SymbolKind.class$);
        // Report-only: the class is surfaced so a human sees it is never
        // constructed, but `--remove` must not delete it or touch its arm.
        expect(decl.removalBlocked, isTrue);
        expect(decl.coupledRemovals, isEmpty);
      },
    );

    test(
      'flag ON: a member matched only by a switch-expression arm is '
      'reported but report-only (removal blocked, no coupled arms)',
      () async {
        final result = await runUnions(flag: true);
        final decl = findByName(result, 'ExpressionOnlySignal');
        expect(decl, isNotNull);
        expect(decl!.removalBlocked, isTrue);
        expect(decl.coupledRemovals, isEmpty);
      },
    );

    test('flag ON: a member matched only by an if-case is reported but '
        'report-only (removal blocked, no coupled arms)', () async {
      final result = await runUnions(flag: true);
      final decl = findByName(result, 'IfCaseOnlySignal');
      expect(decl, isNotNull, reason: 'still reported as dead');
      expect(decl!.removalBlocked, isTrue);
      // Nothing is coupled: `--unused-union-members` never removes arms.
      expect(decl.coupledRemovals, isEmpty);
    });

    test('flag ON: a member that is also constructed is never flagged, nor is '
        'the sealed supertype', () async {
      final names = (await runUnions(
        flag: true,
      )).unused.map((d) => d.qualifiedName).toSet();
      // LiveSignal has a real, non-pattern reference (construction) -> alive.
      expect(names, isNot(contains('LiveSignal')));
      // Signal appears as a parameter/scrutinee type -> a real use.
      expect(names, isNot(contains('Signal')));
    });

    test('flag OFF: every pattern-matched member counts as used (Phase 1 '
        'behaviour is unchanged)', () async {
      final names = (await runUnions(
        flag: false,
      )).unused.map((d) => d.qualifiedName).toSet();
      expect(names, isNot(contains('StatementOnlySignal')));
      expect(names, isNot(contains('ExpressionOnlySignal')));
      expect(names, isNot(contains('IfCaseOnlySignal')));
      expect(names, isNot(contains('LiveSignal')));
      expect(names, isNot(contains('Signal')));
    });
  });

  group('remove-safety guards', () {
    // Scan only the guard fixture; its declarations are self-contained (kept
    // alive by in-file type references), so no cross-file setup is needed.
    Future<FinderResult> runGuards() =>
        runFinder(include: ['lib/guards.dart'], exclude: const []);

    UnusedDeclaration? findByQualified(FinderResult result, String qualified) {
      for (final decl in result.unused) {
        if (decl.qualifiedName == qualified) {
          return decl;
        }
      }
      return null;
    }

    test(
      'an enum consumed only by iterating its `.values` has every value flagged '
      'but removal-blocked (empty-enum guard keeps --remove safe)',
      () async {
        final result = await runGuards();
        // No value is named individually, so with no `.values`-detection every
        // value is flagged dead — but the enum TYPE stays referenced (through
        // that same `.values`), so the empty-enum guard blocks removal instead
        // of emptying the enum. Covers both the qualified `EnumName.values`
        // form (IterableColor) and the implicit bare `values` form
        // (SelfIteratingUnit).
        for (final qualified in const [
          'IterableColor.red',
          'IterableColor.green',
          'IterableColor.blue',
          'SelfIteratingUnit.first',
          'SelfIteratingUnit.second',
        ]) {
          final decl = findByQualified(result, qualified);
          expect(decl, isNotNull, reason: '$qualified should be flagged dead');
          expect(
            decl!.removalBlocked,
            isTrue,
            reason: '$qualified would empty a still-referenced enum',
          );
        }
      },
    );

    test(
      'emptying a still-referenced enum is reported but removal-blocked',
      () async {
        final result = await runGuards();
        for (final qualified in const [
          'EmptyableStatus.pending',
          'EmptyableStatus.settled',
        ]) {
          final decl = findByQualified(result, qualified);
          expect(decl, isNotNull, reason: '$qualified should be flagged dead');
          // Removing every value would leave `enum EmptyableStatus {}`, so the
          // finding is surfaced but --remove must leave it in place.
          expect(
            decl!.removalBlocked,
            isTrue,
            reason: '$qualified would empty a still-referenced enum',
          );
        }
      },
    );

    test(
      'the sole constructor of a live class with final fields is reported but '
      'removal-blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'LabeledBox.new');
        expect(decl, isNotNull, reason: 'the dead constructor is still a find');
        expect(decl!.kind, SymbolKind.constructor);
        // Removing it would strand the `final label` field, so block removal.
        expect(decl.removalBlocked, isTrue);
      },
    );

    test(
      'a super-forwarding sole constructor is reported but removal-blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'ForwardingChild.new');
        expect(decl, isNotNull);
        expect(decl!.kind, SymbolKind.constructor);
        // Removing it would leave an implicit default constructor calling a
        // non-existent zero-arg `super()`, so block removal.
        expect(decl.removalBlocked, isTrue);
      },
    );

    test(
      'a safe sole-constructor removal (no final fields, no super forwarding) '
      'is reported and NOT blocked',
      () async {
        final result = await runGuards();
        final decl = findByQualified(result, 'MutableBag.new');
        expect(decl, isNotNull, reason: 'still a real unused finding');
        // Nothing to strand and no super to break: safe to auto-remove.
        expect(
          decl!.removalBlocked,
          isFalse,
          reason: 'no final fields and no super forwarding',
        );
      },
    );
  });
}
