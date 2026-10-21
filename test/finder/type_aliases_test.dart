/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/copy_tree.dart';

void main() {
  final fixturePath = p.join(Directory.current.path, 'example');
  const fixture = [
    'lib/scenarios/type_aliases.dart',
    'lib/scenarios/type_aliases_uses.dart',
  ];

  Future<FinderResult> run(
    String rootPath, {
    Set<SymbolKind> kinds = FinderOptions.defaultKinds,
  }) => Ciach(
    .new(rootPath: rootPath, includeGlobs: fixture, kinds: kinds),
  ).run();

  test(
    'reports each unused type alias as a `typedef`, and a mixin application class as a `class`',
    () async {
      final result = await run(fixturePath);

      expect(
        [for (final d in result.unused) (d.qualifiedName, d.kind.label)],
        [
          ('OnlyAliased', 'class'),
          ('DeadAlias', 'typedef'),
          ('DeadCallback', 'typedef'),
          ('DeadCompare', 'typedef'),
          ('DeadPair', 'typedef'),
          ('_DeadPrivate', 'typedef'),
          ('Trait', 'mixin'),
          ('DeadMixed', 'class'),
        ],
      );
    },
  );

  test('`--kinds=typedef` reports only the type aliases', () async {
    final result = await run(fixturePath, kinds: {.object});

    expect(result.unused.map((d) => d.qualifiedName), [
      'DeadAlias',
      'DeadCallback',
      'DeadCompare',
      'DeadPair',
      '_DeadPrivate',
    ]);
  });

  test(
    '`--remove` deletes the unused type aliases and leaves code that compiles',
    () async {
      final copy = Directory.systemTemp.createTempSync('ciach_type_aliases_');
      addTearDown(() => copy.deleteSync(recursive: true));
      copyTree(.new(fixturePath), copy);

      removeDeclarations((await run(copy.path)).unused, copy.path);

      expect(
        File(p.join(copy.path, fixture.first)).readAsStringSync(),
        isNot(contains('Dead')),
      );
      final analysis = await Process.run(Platform.resolvedExecutable, [
        'analyze',
        p.join(copy.path, 'lib', 'scenarios'),
      ]);
      expect(analysis.exitCode, 0, reason: '${analysis.stdout}');
      expect((await run(copy.path)).unused, isEmpty);
    },
  );
}
