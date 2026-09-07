@TestOn('!windows')
library;

import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ciach_lsp_test');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // A `dart` that complains and dies, like a compiled ciach spawned as its own
  // server did (#42).
  String fakeDart(String stderrText, int exitCode) {
    final script = File(
      p.join(tmp.path, 'dart'),
    )..writeAsStringSync('#!/bin/sh\necho "$stderrText" >&2\nexit $exitCode\n');
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  test(
    'a server that dies during initialize reports its exit and stderr',
    () async {
      final client = await LspClient.start(
        dartExecutable: fakeDart(
          'Could not find an option named --protocol.',
          2,
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.initialize(tmp.uri),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(
              contains('exited unexpectedly with code 2'),
              contains('Could not find an option named --protocol.'),
              contains(client.dartExecutable),
            ),
          ),
        ),
      );
    },
  );

  test('a silent death says so instead of showing empty stderr', () async {
    final client = await LspClient.start(dartExecutable: fakeDart('', 1));
    addTearDown(client.dispose);

    await expectLater(
      client.initialize(tmp.uri),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          allOf(contains('code 1'), contains('wrote nothing to stderr')),
        ),
      ),
    );
  });
}
