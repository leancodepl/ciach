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
    // The widget fixture is scanned only by the dedicated dead-widget tests;
    // exclude it from the default-run assertions.
    List<String> exclude = const ['lib/widgets.dart', 'lib/unions.dart'],
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
    List<String> exclude = const ['lib/widgets.dart', 'lib/unions.dart'],
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
    });
  });

  test('including operators also reports operator overloads', () async {
    final unused = await findUnused(skipOperators: false);
    expect(unused, containsAll(['Vector2.+', 'Vector2.-']));
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
}
