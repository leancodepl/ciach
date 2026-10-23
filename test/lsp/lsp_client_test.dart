@TestOn('!windows')
library;

import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = .systemTemp.createTempSync('ciach_lsp_test');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // A `dart` that complains and dies, like a compiled ciach spawned as its own
  // server did (#42).
  String fakeDart(String stderrText, int exitCode) {
    final script = File(p.join(tmp.path, 'dart'))
      ..writeAsStringSync('''
#!/bin/sh
echo "$stderrText" >&2
exit $exitCode
''');
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
          isA<AnalysisServerExitedException>().having(
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
        isA<AnalysisServerExitedException>().having(
          (e) => e.message,
          'message',
          allOf(contains('code 1'), contains('wrote nothing to stderr')),
        ),
      ),
    );
  });

  // Fails references like the Dart server: bare error, then a logMessage.
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
          const .new(line: 0, character: 0),
        ),
        throwsA(
          isA<LspRequestException>()
              .having((e) => e.method, 'method', 'textDocument/references')
              .having(
                (e) => e.message,
                'message',
                'Null check operator used on a null value',
              )
              .having(
                (e) => e.detail,
                'detail',
                '#0      ElementReferencesComputer.compute',
              ),
        ),
      );
    },
  );

  // Writes each message it gets to the file named by its first argument. After
  // it gets a workspace folder, it reports idle, then analyzing, then idle.
  String recordingServer(File log) {
    final server = File(p.join(tmp.path, 'recording_server.dart'))
      ..writeAsStringSync(r'''
import 'dart:convert';
import 'dart:io';

void send(Map<String, Object?> message) {
  final body = utf8.encode(jsonEncode({'jsonrpc': '2.0', ...message}));
  stdout.add(utf8.encode('Content-Length: ${body.length}\r\n\r\n'));
  stdout.add(body);
}

void status(bool analyzing) => send({
  'method': r'$/analyzerStatus',
  'params': {'isAnalyzing': analyzing},
});

void main(List<String> args) {
  final log = File(args.first);
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
      log.writeAsStringSync('${jsonEncode(message)}\n', mode: FileMode.append);
      final id = message['id'];
      switch (message['method']) {
        case 'initialize':
          send({'id': id, 'result': {'capabilities': <String, Object?>{}}});
        case 'workspace/didChangeWorkspaceFolders':
          Future.delayed(const Duration(milliseconds: 100), () => status(false));
          Future.delayed(const Duration(milliseconds: 300), () => status(true));
          Future.delayed(const Duration(milliseconds: 600), () => status(false));
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
        '#!/bin/sh\nexec "${Platform.resolvedExecutable}" "${server.path}" "${log.path}"\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  test(
    'rewritten analysis options reach the server before the workspace does',
    () async {
      final log = File(p.join(tmp.path, 'received.jsonl'));
      final options = p.join(tmp.path, 'analysis_options.yaml');
      final client = await LspClient.start(
        dartExecutable: recordingServer(log),
      );
      await client.initialize(tmp.uri, analysisOptions: {options: '{}'});
      final waited = Stopwatch()..start();
      await client.waitForAnalysisComplete();
      expect(
        waited.elapsedMilliseconds,
        greaterThan(400),
        reason:
            'an idle report before the analysis starts must not end the wait',
      );
      await client.dispose();

      final received = [
        for (final line in log.readAsLinesSync())
          jsonDecode(line) as Map<String, Object?>,
      ];
      Map<String, Object?> paramsOf(String method) =>
          received.firstWhere((m) => m['method'] == method)['params']!
              as Map<String, Object?>;
      final methods = [for (final message in received) message['method']];
      final opened = methods.indexOf('textDocument/didOpen');
      final added = methods.indexOf('workspace/didChangeWorkspaceFolders');
      expect(opened, greaterThan(methods.indexOf('initialized')));
      expect(added, greaterThan(opened));

      final startRoot = paramsOf('initialize')['rootUri']! as String;
      expect(startRoot, isNot(tmp.uri.toString()));
      expect(Directory.fromUri(.parse(startRoot)).existsSync(), isFalse);
      expect(paramsOf('textDocument/didOpen'), {
        'textDocument': {
          'uri': File(options).uri.toString(),
          'languageId': 'yaml',
          'version': 1,
          'text': '{}',
        },
      });
      expect(
        (paramsOf('workspace/didChangeWorkspaceFolders')['event']!
            as Map<String, Object?>)['added'],
        [
          {'uri': tmp.uri.toString(), 'name': 'root'},
        ],
      );
    },
  );

  test(
    '`closeAll` closes every open document and returns its URI, and `ensureOpen` opens a closed one again',
    () async {
      final log = File(p.join(tmp.path, 'received.jsonl'));
      final client = await LspClient.start(
        dartExecutable: recordingServer(log),
      );
      await client.initialize(tmp.uri);
      final a = tmp.uri.resolve('a.dart');
      final b = tmp.uri.resolve('b.dart');
      client
        ..didOpen(a, 'a')
        ..didOpen(b, 'b');
      final closed = client.closeAll();
      client.ensureOpen(a, 'a');
      await client.dispose();

      expect(closed, [a, b]);
      final documentMessages = [
        for (final line in log.readAsLinesSync())
          if (jsonDecode(line) case {
            'method': final String method,
            'params': {'textDocument': {'uri': final String uri}},
          } when method.startsWith('textDocument/'))
            (method, uri),
      ];
      expect(documentMessages, [
        ('textDocument/didOpen', a.toString()),
        ('textDocument/didOpen', b.toString()),
        ('textDocument/didClose', a.toString()),
        ('textDocument/didClose', b.toString()),
        ('textDocument/didOpen', a.toString()),
      ]);
    },
  );
}
