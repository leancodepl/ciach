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

import '../support/package_config.dart';

/// A file with a compile error, which ciach lists as not analyzed while the
/// run goes on.
void main() {
  late Directory tmp;
  late String packagePath;

  setUp(() {
    tmp = .systemTemp.createTempSync('ciach_not_analyzed_');
    packagePath = p.join(tmp.path, 'pkg');
    File(p.join(packagePath, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
name: pkg
environment:
  sdk: ^3.10.0
''');
    File(p.join(packagePath, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(packageConfig({'pkg': '.'}));
    File(p.join(packagePath, 'lib', 'a.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('''
class Base {
  void dead() {}
}

void main() => print(Base());

int broken() => missing();
''');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  test(
    'a file with a compile error is reported as a problem at its first error, and the run goes on',
    () async {
      final result = await Ciach(.new(rootPath: packagePath)).run();

      expect(result.unused.map((d) => d.qualifiedName), [
        'Base.dead',
        'broken',
      ]);
      final problem = result.problems.single;
      expect(problem.location, 'lib/a.dart:7:17');
      expect(
        problem.summary,
        'Has compile errors; the declarations that it uses may be reported.',
      );
      // The wording of the message differs between analyzer versions.
      expect(problem.cause, contains("'missing'"));
    },
  );

  test(
    'a file that is not UTF-8, scanned or generated, is reported as unreadable and not as empty, and the run goes on',
    () async {
      for (final name in ['garbled.dart', 'garbled.g.dart']) {
        File(
          p.join(packagePath, 'lib', name),
        ).writeAsBytesSync(const [0xff, 0xfe, 0xfd]);
      }

      final result = await Ciach(.new(rootPath: packagePath)).run();

      expect(
        [
          for (final problem in result.problems)
            if (problem.summary == 'Could not read these files; skipped.')
              problem.location,
        ],
        ['lib/garbled.dart', 'lib/garbled.g.dart'],
      );
      expect(result.emptyFiles, isEmpty);
      expect(result.unused.map((d) => d.qualifiedName), [
        'Base.dead',
        'broken',
      ]);
    },
  );

  group('the CLI', () {
    Future<ProcessResult> runCli([List<String> args = const []]) =>
        Process.run(Platform.resolvedExecutable, [
          'run',
          p.join('bin', 'ciach.dart'),
          packagePath,
          '--no-progress',
          // A local run, whatever CI the test itself is on.
          '--no-ci',
          // The fixture's library is its API.
          '--exported-packages=',
          ...args,
        ]);

    test(
      'lists the file as not analyzed, below the findings, and exits as usual',
      () async {
        final result = await runCli(['--set-exit-if-changed']);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final stdout = result.stdout as String;
        final notAnalyzed = stdout.indexOf('Not analyzed (1)');
        expect(notAnalyzed, isNonNegative, reason: stdout);
        expect(stdout.substring(0, notAnalyzed), contains('Base.dead'));
        expect(
          stdout.substring(notAnalyzed),
          allOf(
            contains(
              '  Has compile errors; the declarations that it uses may be reported.\n',
            ),
            contains('''
    lib/a.dart
      7:17
'''),
            contains('· 1 not analyzed'),
          ),
        );
        // Problems are results, so stderr stays clean.
        expect(result.stderr, isEmpty);
      },
    );

    test('with -v, narrates the problem once as it happens', () async {
      final result = await runCli(['-v']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        '[finder]  lib/a.dart:7:17: '.allMatches(result.stderr as String),
        hasLength(1),
        reason: '${result.stderr}',
      );
    });
  });
}
