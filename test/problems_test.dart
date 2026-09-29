import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/problems.dart';
import 'package:logging/logging.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;
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
      final log = ProblemLog('/pkg');
      await log.collect(() async {
        await Future<void>.delayed(Duration.zero);
        reportProblem(
          'Could not find the references.',
          failure,
          path: '/pkg/lib/a.dart',
          position: const Position(line: 2, character: 4),
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
    final a = ProblemLog('/a');
    final b = ProblemLog('/b');
    await Future.wait([
      a.collect(() async => reportProblem('A', failure, path: '/a/x.dart')),
      b.collect(() async => reportProblem('B', failure, path: '/b/y.dart')),
    ]);
    expect(a.problems.map((p) => p.summary), ['A']);
    expect(b.problems.map((p) => p.summary), ['B']);
  });

  test('a file system error reads as what the OS said', () async {
    final log = ProblemLog('/pkg');
    await log.collect(
      () async => reportProblem(
        'Could not read.',
        const FileSystemException(
          'Cannot open file',
          '/pkg/a.dart',
          OSError('Permission denied', 13),
        ),
        path: '/pkg/a.dart',
      ),
    );
    expect(log.problems.single.cause, 'Permission denied');
  });

  test(
    'each is logged as a warning carrying it; outside a run, only that',
    () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      reportProblem('Lost.', failure, path: '/pkg/lib/a.dart');
      await pumpEventQueue();

      final record = records.single;
      expect(record.level, Level.WARNING);
      expect(record.loggerName, 'ciach.problems');
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
