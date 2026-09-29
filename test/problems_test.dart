import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/problems.dart';
import 'package:test/test.dart';

void main() {
  const failure = LspRequestException(
    'textDocument/references',
    'Null check operator used on a null value',
    detail: '#0      compute',
  );

  test(
    'a run collects what it reports, however deep, relative to its root',
    () async {
      final log = ProblemCollector('/pkg');
      await log.collect(() async {
        await Future<void>.delayed(.zero);
        recordProblem(
          'Could not find the references.',
          failure,
          path: '/pkg/lib/a.dart',
          position: const .new(line: 2, character: 4),
          name: 'A.foo',
        );
      });

      final problem = log.problems.single;
      expect(problem.location, 'lib/a.dart:3:5');
      expect(problem.name, 'A.foo');
      expect(problem.cause, 'Null check operator used on a null value');
      expect(problem.detail, '#0      compute');
    },
  );

  test('runs side by side keep their own', () async {
    final a = ProblemCollector('/a');
    final b = ProblemCollector('/b');
    await Future.wait([
      a.collect(() async => recordProblem('A', failure, path: '/a/x.dart')),
      b.collect(() async => recordProblem('B', failure, path: '/b/y.dart')),
    ]);
    expect(a.problems.map((p) => p.summary), ['A']);
    expect(b.problems.map((p) => p.summary), ['B']);
  });

  test('a file system error reads as what the OS said', () async {
    final log = ProblemCollector('/pkg');
    await log.collect(
      () async => recordProblem(
        'Could not read.',
        const FileSystemException(
          'Cannot open file',
          '/pkg/a.dart',
          .new('Permission denied', 13),
        ),
        path: '/pkg/a.dart',
      ),
    );
    expect(log.problems.single.cause, 'Permission denied');
  });

  test(
    'each is narrated at FINE, carrying it; outside a run, only that',
    () async {
      final records = <LogRecord>[];
      final level = Logger.root.level;
      Logger.root.level = .ALL;
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(() {
        Logger.root.level = level;
        return subscription.cancel();
      });

      recordProblem('Lost.', failure, path: '/pkg/lib/a.dart');
      await pumpEventQueue();

      final record = records.single;
      expect(record.level, Level.FINE);
      expect(record.loggerName, 'ciach.finder');
      expect(
        record.object,
        isA<AnalysisProblem>().having(
          (p) => p.filePath,
          'filePath',
          '/pkg/lib/a.dart',
        ),
      );
    },
  );
}
