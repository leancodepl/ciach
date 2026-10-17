/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.join(Directory.current.path, 'example');
  final fixtureLines = File(
    p.join(fixturePath, 'lib/scenarios/operators.dart'),
  ).readAsLinesSync();

  /// The finding for the declaration on the only line of the fixture that
  /// contains [code], within the declaration of [container] when it is given.
  ({String name, int line}) declaredAt(
    String name,
    String code, {
    String? container,
  }) {
    final (start, end) =
        container?.let((container) {
          final start = fixtureLines.indexWhere(
            (line) => line.startsWith('class $container'),
          );
          return (
            start,
            fixtureLines.indexWhere((line) => line.startsWith('}'), start),
          );
        }) ??
        (0, fixtureLines.length);
    final lines = [
      for (final (i, line) in fixtureLines.indexed)
        if (i >= start && i < end && line.contains(code)) i + 1,
    ];
    expect(lines, hasLength(1), reason: code);
    return (name: name, line: lines.single);
  }

  Future<Set<({String name, int line})>> findUnused(
    List<String> include, {
    bool skipOverrides = true,
  }) async {
    final result = await Ciach(
      .new(
        rootPath: fixturePath,
        includeGlobs: include,
        skipOverrides: skipOverrides,
      ),
    ).run();
    return {
      for (final declaration in result.unused)
        (name: declaration.qualifiedName, line: declaration.line),
    };
  }

  const noneUsed = [
    '+(',
    '-(N',
    '-()',
    '*(',
    '/(',
    '%(',
    '~/(',
    '&(',
    '|(',
    '^(',
    '~()',
    '<<(',
    '>>(',
    '>>>(',
    '<(',
    '<=(',
    '>(',
    '>=(',
    '[](',
    '[]=(',
  ];

  Set<({String name, int line})> expected() => {
    for (final operator in noneUsed)
      declaredAt(
        'NoneUsed.${operator.substring(0, operator.indexOf('('))}',
        'operator $operator',
        container: 'NoneUsed',
      ),
    declaredAt('UnaryMinusOnly.-', 'UnaryMinusOnly operator -(UnaryMinusOnly'),
    declaredAt('Shape.+', 'Shape operator +(Shape other);'),
    declaredAt('onlyFromDeadCode', 'onlyFromDeadCode() =>'),
    declaredAt('OnlyUsedFromDeadCode.*', 'OnlyUsedFromDeadCode operator *('),
  };

  test(
    'reports only the operators that no expression or relational pattern uses',
    () async {
      expect(
        await findUnused(const [
          'lib/scenarios/operators.dart',
          'lib/scenarios/operators_uses.dart',
        ]),
        expected(),
      );
    },
  );

  test(
    'counts the uses of an operator in a file that is not scanned',
    () async {
      expect(
        await findUnused(const ['lib/scenarios/operators.dart']),
        expected(),
      );
    },
  );

  test(
    'with `--also overrides`, reports an unused override of an operator but never `==`',
    () async {
      expect(
        await findUnused(const [
          'lib/scenarios/operators.dart',
          'lib/scenarios/operators_uses.dart',
        ], skipOverrides: false),
        {
          ...expected(),
          declaredAt('Square.+', 'Shape operator +(Shape other) =>'),
        },
      );
    },
  );
}
