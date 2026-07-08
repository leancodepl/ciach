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
    bool ignoreDocReferences = false,
    Set<SymbolKind>? kinds,
    List<String> exclude = const [],
    List<String> include = const [],
  }) => Ciach(
    .new(
      rootPath: fixturePath,
      includePublic: includePublic,
      skipOverrides: skipOverrides,
      skipOperators: skipOperators,
      ignoreDocReferences: ignoreDocReferences,
      kinds: kinds ?? FinderOptions.defaultKinds,
      excludeGlobs: exclude,
      includeGlobs: include,
    ),
  ).run();

  Future<Set<String>> findUnused({
    bool includePublic = true,
    bool skipOverrides = true,
    bool skipOperators = true,
    bool ignoreDocReferences = false,
    Set<SymbolKind>? kinds,
    List<String> exclude = const [],
    List<String> include = const [],
  }) async {
    final result = await runFinder(
      includePublic: includePublic,
      skipOverrides: skipOverrides,
      skipOperators: skipOperators,
      ignoreDocReferences: ignoreDocReferences,
      kinds: kinds,
      exclude: exclude,
      include: include,
    );
    return result.unused.map((d) => d.qualifiedName).toSet();
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

  test('ignoring doc references also reports declarations only mentioned in '
      'a doc comment link', () async {
    final unused = await findUnused(ignoreDocReferences: true);
    expect(unused, contains('_docOnlyMentioned'));
  });

  test(
    'by default, a doc comment link keeps a declaration looking used',
    () async {
      final unused = await findUnused();
      expect(unused, isNot(contains('_docOnlyMentioned')));
    },
  );

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

  test('exclude globs remove files from the scan', () async {
    // Excluding lib leaves only bin/app.dart, whose only declaration is the
    // skipped `main`, so nothing is reported.
    expect(await findUnused(exclude: ['lib/**']), isEmpty);
  });
}
