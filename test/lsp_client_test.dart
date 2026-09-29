@TestOn('!windows')
library;

import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show Position;
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

  // A server that fails `textDocument/references` the way the Dart one does:
  // a bare error response, then the exception in `window/logMessage`.
  String failingReferencesServer() {
    final server = File(p.join(tmp.path, 'server.dart'))
      ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

void send(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
  stdout.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
}

void main() {
  var buffer = <int>[];
  stdin.listen((chunk) {
    buffer.addAll(chunk);
    while (true) {
      final text = latin1.decode(buffer);
      final headerEnd = text.indexOf('\r\n\r\n');
      if (headerEnd < 0) return;
      final length = int.parse(
        RegExp(r'Content-Length: (\d+)').firstMatch(text)!.group(1)!,
      );
      final start = headerEnd + 4;
      if (buffer.length < start + length) return;
      final message = jsonDecode(
        utf8.decode(buffer.sublist(start, start + length)),
      ) as Map<String, Object?>;
      buffer = buffer.sublist(start + length);
      final id = message['id'];
      switch (message['method']) {
        case 'initialize':
          send({'id': id, 'result': {'capabilities': <String, Object?>{}}});
        case 'textDocument/references':
          const error = 'An error occurred while handling '
              'textDocument/references request';
          send({
            'id': id,
            'error': {'code': -32001, 'message': error},
          });
          send({
            'method': 'window/logMessage',
            'params': {
              'type': 1,
              'message': '$error: Null check operator used on a null value\n'
                  '#0      ElementReferencesComputer.compute',
            },
          });
        case 'shutdown':
          send({'id': id, 'result': null});
        case 'exit':
          exit(0);
      }
    }
  });
}
''');
    final script = File(p.join(tmp.path, 'dart'))
      ..writeAsStringSync(
        '#!/bin/sh\nexec "${Platform.resolvedExecutable}" "${server.path}"\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  test(
    'a request the server threw on carries the exception it logged',
    () async {
      final client = await LspClient.start(
        dartExecutable: failingReferencesServer(),
      );
      addTearDown(client.dispose);
      await client.initialize(tmp.uri);

      await expectLater(
        client.references(
          tmp.uri.resolve('a.dart'),
          const Position(line: 0, character: 0),
        ),
        throwsA(
          isA<AnalysisServerException>()
              .having(
                (e) => e.message,
                'message',
                'An error occurred while handling textDocument/references '
                    'request',
              )
              .having(
                (e) => e.detail,
                'detail',
                allOf(
                  startsWith('Null check operator used on a null value'),
                  contains('ElementReferencesComputer.compute'),
                ),
              ),
        ),
      );
    },
  );
}
