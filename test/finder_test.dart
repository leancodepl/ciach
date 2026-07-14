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
    List<String> exclude = const [],
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
    List<String> exclude = const [],
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
      'Unconstructed.new',
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

  test('skips call methods and private constructors by default', () async {
    final unused = await findUnused();
    // `Multiplier.call` is invoked via implicit-call syntax (`multiplier(21)`
    // in bin/app.dart), which a reference search can't resolve back to the
    // declaration — skipped like an operator, so never reported as unused.
    expect(unused, isNot(contains('Multiplier.call')));
    // A private constructor prevents instantiation and is intentionally never
    // referenced — skipped rather than reported as unused.
    expect(unused, isNot(contains('MathConstants._')));
    // The rest of the callable/utility fixture is genuinely used, so nothing
    // else from it should show up either.
    expect(unused, isNot(contains('Multiplier')));
    expect(unused, isNot(contains('Multiplier.new')));
    expect(unused, isNot(contains('Multiplier.factor')));
    expect(unused, isNot(contains('MathConstants')));
    expect(unused, isNot(contains('MathConstants.pi')));
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
    // Unnamed constructor: `Class.new`.
    expect(unused, contains('Unconstructed.new'));
  });

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
    expect(await findUnused(kinds: {.class$}), {'UnusedClass'});
  });

  test(
    'reports unused enum values under the enum-value kind, not enum',
    () async {
      final result = await runFinder();
      final enumValues = {
        for (final d in result.unused)
          if (d.kind == SymbolKind.enumMember) d.qualifiedName,
      };
      // The fixture's unused enum values carry the enumMember kind...
      expect(enumValues, {'Direction.south', 'Direction.west'});
      // ...and are therefore not lumped in with the enum-type kind.
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
      // `-k enum-value` lists the unused enum values.
      expect(await findUnused(kinds: {.enumMember}), {
        'Direction.south',
        'Direction.west',
      });
      // `-k enum` no longer picks them up (the fixture has no unused enum type).
      expect(await findUnused(kinds: {.enum$}), isEmpty);
    },
  );

  test('exclude globs remove files from the scan', () async {
    // Excluding lib leaves only bin/app.dart, whose only declaration is the
    // skipped `main`, so nothing is reported.
    expect(await findUnused(exclude: ['lib/**']), isEmpty);
  });
}
