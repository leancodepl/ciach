@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/settle/unused_parameters.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/example_package.dart';

/// Runs the finder on `example/lib/scenarios/unused_parameters.dart`, whose
/// comments say which parameters are reported.
void main() {
  const fixture = 'lib/scenarios/unused_parameters.dart';

  setUpAll(resolveExample);

  Future<FinderResult> run({
    String? rootPath,
    Set<SymbolKind> kinds = FinderOptions.defaultKinds,
    bool includePublic = true,
  }) => Ciach(
    .new(
      rootPath: rootPath ?? examplePath,
      includeGlobs: const [fixture],
      kinds: kinds,
      includePublic: includePublic,
    ),
  ).run();

  Set<String> parameters(FinderResult result) => {
    for (final finding in result.unused)
      if (finding.kind == parameterKind) finding.qualifiedName,
  };

  test(
    'reports the parameters that only calls use and that the bodies never read',
    () async {
      expect(parameters(await run()), {
        'log.level',
        '_sum.unused',
        'parse.strict',
        'forward.label',
        'onTap.index',
        'docLinked.unused',
        'Printer.write.prefix',
        'Printer.repeat.count',
        'Account.new.currency',
        'Shouting.shout.times',
        'Level.new.weight',
      });
    },
  );

  test('reports a parameter as report-only, with a hint', () async {
    final log = (await run()).unused.singleWhere(
      (finding) => finding.qualifiedName == 'log.level',
    );

    expect(
      (
        log.kind.label,
        log.filePath,
        log.line,
        log.column,
        log.isPrivate,
        log.removalBlocked,
        log.hint,
      ),
      ('parameter', fixture, 12, 30, false, true, UnusedParameters.hint),
    );
  });

  test(
    'reports an unused function, not its parameter, among the other kinds',
    () async {
      final names = (await run()).unused.map((f) => f.qualifiedName);

      expect(names, contains('deadFunction'));
      expect(names, isNot(contains('deadFunction.unused')));
    },
  );

  test(
    'with `--kinds parameter`, reports the parameter of a function that the kinds leave out',
    () async {
      final result = await run(kinds: const {parameterKind});

      expect(result.unused.map((f) => f.kind).toSet(), {parameterKind});
      expect(parameters(result), contains('deadFunction.unused'));
    },
  );

  test('reports no parameter when `--kinds` leaves out `parameter`', () async {
    final result = await run(kinds: const {.function, .method});

    expect(parameters(result), isEmpty);
  });

  test(
    'with `--no-public`, reports only the parameters of private functions',
    () async {
      expect(parameters(await run(includePublic: false)), {'_sum.unused'});
    },
  );

  test('`--remove` leaves the parameters in place', () async {
    final copy = Directory.systemTemp.createTempSync('ciach_parameters_');
    addTearDown(() => copy.deleteSync(recursive: true));
    for (final path in [
      fixture,
      'pubspec.yaml',
      '.dart_tool/package_config.json',
    ]) {
      File(p.join(examplePath, path)).copySync(
        (File(
          p.join(copy.path, path),
        )..parent.createSync(recursive: true)).path,
      );
    }
    final result = await run(rootPath: copy.path, kinds: const {parameterKind});
    expect(parameters(result), isNotEmpty);

    removeDeclarations(result.unused, copy.path);

    expect(
      File(p.join(copy.path, fixture)).readAsStringSync(),
      File(p.join(examplePath, fixture)).readAsStringSync(),
    );
  });
}
