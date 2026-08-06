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
    // The scenario fixtures under lib/scenarios/ are scanned only by their
    // dedicated tests; exclude them from the default-run assertions.
    List<String> exclude = const ['lib/scenarios/**'],
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
    List<String> exclude = const ['lib/scenarios/**'],
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

  test(
    'reports unused enum values under the enum-value kind, not enum',
    () async {
      final result = await runFinder();
      final enumValues = {
        for (final d in result.unused)
          if (d.kind == SymbolKind.enumMember) d.qualifiedName,
      };
      expect(enumValues, {'Direction.south', 'Direction.west'});
      final enumTypes = {
        for (final d in result.unused)
          if (d.kind == SymbolKind.enum$) d.qualifiedName,
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

  group('dead widget classes', () {
    // Scan only the widget fixture; cross-package references (e.g. the live
    // widget constructed in bin/app.dart) still resolve, since the analysis
    // server analyses the whole package regardless of the candidate filter.
    Future<FinderResult> runWidgets() =>
        runFinder(include: ['lib/scenarios/widgets.dart'], exclude: const []);

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
        includeGlobs: const ['lib/scenarios/unions.dart'],
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
        runFinder(include: ['lib/scenarios/guards.dart'], exclude: const []);

    UnusedDeclaration? findByQualified(FinderResult result, String qualified) {
      for (final decl in result.unused) {
        if (decl.qualifiedName == qualified) {
          return decl;
        }
      }
      return null;
    }

    test(
      'emptying a still-referenced enum is reported but removal-blocked',
      () async {
        final result = await runGuards();
        // No value is named individually and `.values` is never iterated, but
        // the enum TYPE stays referenced, so the empty-enum guard blocks removal
        // instead of emptying the enum. (Enums reached via `.values` are
        // instead treated as used and never reported — see the `enum `.values`
        // detection fix` group.)
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

  group('enum `.values` detection fix', () {
    // Scan only the enum-`.values` fixture (enums kept alive by in-file refs).
    Future<FinderResult> runEnumValues() => runFinder(
      include: ['lib/scenarios/enum_values.dart'],
      exclude: const [],
    );

    test(
      'enum values reached only via qualified `EnumName.values` iteration are '
      'never flagged',
      () async {
        final names = (await runEnumValues()).unused
            .map((d) => d.qualifiedName)
            .toSet();
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
        final names = result.unused.map((d) => d.qualifiedName).toSet();
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

  group('freezed union deserialization-only arms', () {
    // Whole-package analysis still resolves the cross-file `Base.fromJson` use.
    Future<Set<String>> runFreezedUnions() async {
      final result = await runFinder(
        include: const ['lib/scenarios/freezed_unions.dart'],
        exclude: const [],
      );
      return result.unused.map((d) => d.qualifiedName).toSet();
    }

    test('a redirecting-factory arm of a @Freezed union with a referenced '
        'fromJson is treated as used (was a false positive)', () async {
      final names = await runFreezedUnions();
      // Built only by the generated fromJson, never hand-called.
      expect(names, isNot(contains('Base.contestEvent')));
      expect(names, isNot(contains('Base.matchEvent')));
    });

    test('arms of a @freezed union with NO fromJson stay flagged', () async {
      final names = await runFreezedUnions();
      // `Standalone` is never deserialized, so its arms are genuinely dead.
      expect(names, contains('Standalone.left'));
      expect(names, contains('Standalone.right'));
    });

    test(
      'a redirecting factory on a NON-annotated class stays flagged',
      () async {
        final names = await runFreezedUnions();
        // The fix only exempts `@freezed`/`@Freezed` unions.
        expect(names, contains('Plain.make'));
      },
    );

    test(
      'a never-dispatched arm of a deserialized union is also suppressed '
      '(documented over-suppression: indistinguishable from a live arm)',
      () async {
        final names = await runFreezedUnions();
        // Genuinely dead, but statically indistinguishable from a live deser-only arm.
        expect(names, isNot(contains('Base.deadArm')));
      },
    );
  });

  group('toJson/fromJson serialization hooks', () {
    // Whole-package analysis still resolves the cross-file uses from bin/app.dart.
    Future<Set<String>> runSerialization({bool reportToJson = false}) async {
      final result = await Ciach(
        .new(
          rootPath: fixturePath,
          includeGlobs: const ['lib/scenarios/serialization.dart'],
          reportToJson: reportToJson,
        ),
      ).run();
      return result.unused.map((d) => d.qualifiedName).toSet();
    }

    test('a toJson() is exempt by convention, for any class, annotated or '
        'not — jsonEncode can call it invisibly', () async {
      final names = await runSerialization();
      expect(names, isNot(contains('Plain.toJson')));
      expect(names, isNot(contains('Profile.toJson')));
    });

    test('a toJson() returning a non-Map JSON value — a List or a primitive — '
        'is exempt too, since those are valid json values', () async {
      final names = await runSerialization();
      expect(names, isNot(contains('Listy.toJson')));
      expect(names, isNot(contains('Stringy.toJson')));
    });

    test('a toJson() returning an unrelated domain type is not a JSON hook, so '
        'an unused one stays flagged even without the flag', () async {
      expect(await runSerialization(), contains('Domainy.toJson'));
    });

    test(
      'an unused fromJson is still reported, even on an annotated type',
      () async {
        final names = await runSerialization();
        expect(names, contains('Plain.fromJson'));
        expect(names, contains('Profile.fromJson'));
        expect(names, contains('Point.fromJson'));
      },
    );

    test(
      'a toJson with a visible `.toJson()` caller is never flagged',
      () async {
        expect(await runSerialization(), isNot(contains('Visible.toJson')));
        expect(
          await runSerialization(reportToJson: true),
          isNot(contains('Visible.toJson')),
        );
      },
    );

    test('--report-tojson re-enables reporting a dead toJson', () async {
      final names = await runSerialization(reportToJson: true);
      expect(names, contains('Plain.toJson'));
      expect(names, contains('Profile.toJson'));
      // The non-Map JSON-value hooks re-appear under the flag as well.
      expect(names, contains('Listy.toJson'));
      expect(names, contains('Stringy.toJson'));
      // fromJson reporting is independent of the toJson flag.
      expect(names, contains('Plain.fromJson'));
    });
  });

  group('cross-library reference recovery', () {
    // The consumer file must be scanned too, or the recovery can't see the
    // usage sites the reference index misses.
    Future<FinderResult> runXrefResult() => runFinder(
      include: const [
        'lib/scenarios/xref_shapes.dart',
        'lib/scenarios/xref_event.dart',
        'lib/scenarios/xref_analytics.dart',
        'lib/scenarios/xref_uses.dart',
      ],
      exclude: const [],
    );

    Future<Set<String>> runXref() async =>
        (await runXrefResult()).unused.map((d) => d.qualifiedName).toSet();

    test('a getter/field used only by a cross-file object pattern is not '
        'flagged', () async {
      final names = await runXref();
      expect(names, isNot(contains('XrefLoadedState.hasActive')));
      expect(names, isNot(contains('XrefLoadedState.ready')));
    });

    test(
      'a same-file object-pattern reference still keeps a getter alive',
      () async {
        expect(await runXref(), isNot(contains('XrefLoadedState.localFlag')));
      },
    );

    test(
      'an enum value used only via a cross-library dot-shorthand is not flagged',
      () async {
        expect(await runXref(), isNot(contains('XrefEvent.signOut')));
      },
    );

    test('a normally-referenced enum value is not flagged', () async {
      expect(await runXref(), isNot(contains('XrefEvent.signIn')));
    });

    test(
      'genuinely-dead members are still flagged — the recovery did not blind '
      'the detector',
      () async {
        final names = await runXref();
        expect(names, contains('XrefLoadedState.deadShapeGetter'));
        expect(names, contains('XrefEvent.deadEvent'));
      },
    );

    test('each recovered reference is surfaced as a warning; normal and '
        'genuinely-dead declarations are not', () async {
      final result = await runXrefResult();
      final warned = result.recoveredReferences
          .map((w) => w.qualifiedName)
          .toSet();
      // Confirmed used by the secondary check.
      expect(
        warned,
        containsAll([
          'XrefLoadedState.hasActive',
          'XrefLoadedState.ready',
          'XrefEvent.signOut',
        ]),
      );
      // Normally referenced -> not recovered, no warning.
      expect(warned, isNot(contains('XrefEvent.signIn')));
      expect(warned, isNot(contains('XrefLoadedState.localFlag')));
      // Genuinely dead -> stays a finding, not a warning.
      expect(warned, isNot(contains('XrefLoadedState.deadShapeGetter')));
      expect(warned, isNot(contains('XrefEvent.deadEvent')));
      // The warning carries the confirmed usage location and the hedge.
      final signOut = result.recoveredReferences.firstWhere(
        (w) => w.qualifiedName == 'XrefEvent.signOut',
      );
      expect(signOut.usageFilePath, endsWith('xref_uses.dart'));
      expect(signOut.message, contains('likely a Dart SDK find-references'));
    });
  });

  group('same-simple-name collision recovery', () {
    // Two members share the simple name `status`: one used only from another
    // file (must be recovered) and one never used (must stay flagged). Guards
    // the definition position-matching that tells them apart.
    Future<FinderResult> runCollision() => runFinder(
      include: const [
        'lib/scenarios/xref_collision.dart',
        'lib/scenarios/xref_collision_uses.dart',
      ],
      exclude: const [],
    );

    test(
      'recovers the used member and still flags the dead namesake',
      () async {
        final result = await runCollision();
        final unused = result.unused.map((d) => d.qualifiedName).toSet();
        final warned = result.recoveredReferences
            .map((w) => w.qualifiedName)
            .toSet();
        // The genuinely-dead namesake is still reported.
        expect(unused, contains('DeadState.status'));
        // The used-only-cross-file namesake is recovered, not reported.
        expect(unused, isNot(contains('LiveState.status')));
        expect(warned, contains('LiveState.status'));
        expect(warned, isNot(contains('DeadState.status')));
      },
    );
  });

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

    Future<FinderResult> runShorthandsResult() => runFinder(
      include: const [
        'lib/scenarios/dot_shorthands.dart',
        'lib/scenarios/dot_shorthand_uses.dart',
      ],
      exclude: const [],
    );

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

  group('annotation detection ignores comments', () {
    Future<Set<String>> runCommentAnnotations() async {
      final result = await runFinder(
        include: const ['lib/scenarios/comment_annotations.dart'],
        exclude: const [],
      );
      return result.unused.map((d) => d.qualifiedName).toSet();
    }

    test(
      'a doc comment mentioning @override does not skip the declaration',
      () {
        return expectLater(
          runCommentAnnotations(),
          completion(contains('deadOverrideInDoc')),
        );
      },
    );

    test('a trailing comment mentioning @override does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideTrailing')),
      );
    });

    test('a blank-separated comment mentioning @override does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideBlankSeparated')),
      );
    });

    test('a doc comment mentioning vm:entry-point does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointInDoc')),
      );
    });

    test('a trailing comment mentioning vm:entry-point does not skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointTrailing')),
      );
    });

    test('a blank-separated comment mentioning vm:entry-point does not skip '
        'it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointBlankSeparated')),
      );
    });

    test('a file-header block mentioning both literals does not skip the first '
        'declaration', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadAfterHeaderBlock')),
      );
    });

    test('an unprefixed block-comment line mentioning @override does not skip '
        'it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadOverrideBareBlock')),
      );
    });

    test('an unprefixed block-comment line mentioning vm:entry-point does not '
        'skip it', () {
      return expectLater(
        runCommentAnnotations(),
        completion(contains('deadEntryPointBareBlock')),
      );
    });

    test('a real @pragma(vm:entry-point) is still skipped — the string literal '
        'survives comment-stripping', () async {
      final names = await runCommentAnnotations();
      expect(names, isNot(contains('liveByRealPragma')));
    });
  });
}
