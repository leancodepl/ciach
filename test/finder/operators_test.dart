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

import '../support/temp_package.dart';

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
    declaredAt('Ordered.>', 'bool operator >(Ordered other)'),
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

  /// The names of the declarations that a scan of a package reports, with
  /// [library] as `lib/ops.dart`, [main] as `bin/main.dart` and the other
  /// [files] by their paths.
  Future<Set<String>> findUnusedIn({
    required String library,
    required String main,
    Map<String, String> files = const {},
    bool skipOverrides = true,
    bool includePublic = true,
    List<String> exportedPackages = const [],
  }) async {
    final root = writeTempPackage('ops', {
      'lib/ops.dart': library,
      'bin/main.dart': main,
      ...files,
    });
    final result = await Ciach(
      .new(
        rootPath: root.path,
        skipOverrides: skipOverrides,
        includePublic: includePublic,
        exportedPackages: exportedPackages,
      ),
    ).run();
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  test(
    'checks an operator whose name follows the `operator` keyword on the next line or after a comment',
    () async {
      // `dart format` would join the lines, so the fixture is written here.
      expect(
        await findUnusedIn(
          library: '''
class Split {
  const Split();

  Split operator
  -(Split other) => this;
  Split operator /* divides */ /(Split other) => this;
  Split operator
  +(Split other) => this;
  Split operator *(Split other) => this;
}
''',
          main: '''
import 'package:ops/ops.dart';

void main() => print((const Split() + const Split()) / const Split());
''',
        ),
        {'Split.-', 'Split.*'},
      );
    },
  );

  /// `C` overrides the operators of `B`, which overrides those of `A`, and
  /// code uses `+` only through `B`.
  const chain = '''
class A {
  const A();

  A operator +(A other) => this;
  A operator -(A other) => this;
}

class B extends A {
  const B();

  @override
  A operator +(A other) => this;
  @override
  A operator -(A other) => this;
}

class C extends B {
  const C();

  @override
  A operator +(A other) => this;
  @override
  A operator -(A other) => this;
}
''';
  const chainUses = '''
import 'package:ops/ops.dart';

void main() => print([const B() + const A(), const C()]);
''';

  test(
    'counts a use through the middle class of an override chain for `A.+`, and reports the unused `A.-`',
    () async {
      expect(await findUnusedIn(library: chain, main: chainUses), {'A.-'});
    },
  );

  test(
    'with `--also overrides`, counts a use through the middle class of an override chain for every `+`, and reports every `-`',
    () async {
      expect(
        await findUnusedIn(
          library: chain,
          main: chainUses,
          skipOverrides: false,
        ),
        {'A.-', 'B.-', 'C.-'},
      );
    },
  );

  test(
    "with `--also overrides`, never reports an operator that overrides one from the SDK through a class that doesn't declare it",
    () async {
      expect(
        await findUnusedIn(
          library: '''
import 'dart:collection';

abstract class Middle extends ListBase<int> {}

class Leaf extends Middle {
  @override
  int length = 0;

  @override
  int operator [](int index) => index;

  @override
  void operator []=(int index, int value) {}
}
''',
          main: '''
import 'package:ops/ops.dart';

void main() => print(Leaf().length);
''',
          skipOverrides: false,
        ),
        isEmpty,
      );
    },
  );

  /// `Public` is in the package's API, `_Private` is private, and `Hidden` is
  /// in a file that the package doesn't export. Each has an unused `+` and an
  /// unused method.
  const visibility = '''
import 'src/hidden.dart';

class Public {
  const Public();

  Public operator +(Public other) => this;
  void method() {}
}

class _Private {
  const _Private();

  _Private operator +(_Private other) => this;
  void method() {}
}

void useHidden() => print([const _Private(), const Hidden()]);
''';
  const visibilityFiles = {
    'lib/src/hidden.dart': '''
class Hidden {
  const Hidden();

  Hidden operator +(Hidden other) => this;
  void method() {}
}
''',
  };
  const visibilityUses = '''
import 'package:ops/ops.dart';

void main() {
  print(const Public());
  useHidden();
}
''';

  test(
    'with `exported-packages`, leaves out the operators of an exported class and reports the others, as it does methods',
    () async {
      expect(
        await findUnusedIn(
          library: visibility,
          main: visibilityUses,
          files: visibilityFiles,
          exportedPackages: const ['**'],
        ),
        {'_Private.+', '_Private.method', 'Hidden.+', 'Hidden.method'},
      );
    },
  );

  test(
    'with `--no-public`, reports no operator, because the name of an operator is public, as it reports no public method of a private class',
    () async {
      expect(
        await findUnusedIn(
          library: visibility,
          main: visibilityUses,
          files: visibilityFiles,
          includePublic: false,
        ),
        isEmpty,
      );
    },
  );
}
