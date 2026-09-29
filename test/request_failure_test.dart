@TestOn('!windows')
@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late String packagePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ciach_request_failure_');
    packagePath = p.join(tmp.path, 'pkg');
    File(p.join(packagePath, 'pubspec.yaml'))
      ..createSync(recursive: true)
      ..writeAsStringSync('name: pkg\nenvironment:\n  sdk: ^3.10.0\n');
    File(p.join(packagePath, '.dart_tool', 'package_config.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        '{"configVersion": 2, "packages": [{"name": "pkg", "rootUri": "../", '
        '"packageUri": "lib/", "languageVersion": "3.10"}]}',
      );
    // The fake server fails the reference lookup on line 1.
    File(p.join(packagePath, 'lib', 'a.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync('void brokenLookup() {}\nvoid reallyUnused() {}\n');
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  // The real language server, except that references at line 1 fail like the
  // Dart server's do (or, with [die], the server exits).
  String proxyDart({bool die = false}) {
    final proxy = File(p.join(tmp.path, 'proxy.dart'))
      ..writeAsStringSync('''
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const die = $die;

/// Splits a Content-Length-framed stream into message bodies.
Stream<String> frames(Stream<List<int>> input) async* {
  var buffer = <int>[];
  await for (final chunk in input) {
    buffer.addAll(chunk);
    while (true) {
      final text = latin1.decode(buffer);
      final headerEnd = text.indexOf('\\r\\n\\r\\n');
      if (headerEnd < 0) break;
      final length = int.parse(
        RegExp(r'Content-Length: (\\d+)').firstMatch(text)!.group(1)!,
      );
      final start = headerEnd + 4;
      if (buffer.length < start + length) break;
      yield utf8.decode(buffer.sublist(start, start + length));
      buffer = buffer.sublist(start + length);
    }
  }
}

void send(IOSink sink, String body) {
  final bytes = utf8.encode(body);
  sink.add(utf8.encode('Content-Length: \${bytes.length}\\r\\n\\r\\n'));
  sink.add(bytes);
}

Future<void> main(List<String> args) async {
  final server = await Process.start(${_quoted(Platform.resolvedExecutable)}, args);
  server.stderr.listen(stderr.add);
  unawaited(frames(server.stdout).forEach((body) => send(stdout, body)));
  unawaited(server.exitCode.then(exit));
  await for (final body in frames(stdin)) {
    final message = jsonDecode(body) as Map<String, Object?>;
    final params = message['params'];
    if (message['method'] == 'textDocument/references' &&
        params is Map &&
        (params['position'] as Map)['line'] == 0) {
      if (die) {
        stderr.writeln('Injected crash');
        exit(3);
      }
      const error = 'An error occurred while handling '
          'textDocument/references request';
      send(stdout, jsonEncode({
        'jsonrpc': '2.0',
        'id': message['id'],
        'error': {'code': -32001, 'message': error},
      }));
      send(stdout, jsonEncode({
        'jsonrpc': '2.0',
        'method': 'window/logMessage',
        'params': {
          'type': 1,
          'message': '\$error: Injected failure\\n#0      injected',
        },
      }));
      continue;
    }
    send(server.stdin, body);
  }
}
''');
    final script = File(p.join(tmp.path, 'dart'))
      ..writeAsStringSync(
        '#!/bin/sh\nexec ${_quoted(Platform.resolvedExecutable)} '
        '${_quoted(proxy.path)} "\$@"\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    return script.path;
  }

  test('a declaration the server fails on is kept and reported as a problem, '
      'and the run goes on', () async {
    final result = await Ciach(
      .new(rootPath: packagePath, dartExecutable: proxyDart()),
    ).run();

    expect(result.unused.map((d) => d.name), ['reallyUnused']);
    expect(result.declarationsChecked, 1);
    final problem = result.problems.single;
    expect(problem.name, 'brokenLookup');
    expect(problem.location, 'lib/a.dart:1:6');
    expect(problem.summary, 'Could not find references; kept.');
    expect(problem.cause, 'Injected failure');
    expect(problem.detail, '#0      injected');
  });

  test('a server that dies stops the run with its exit', () async {
    await expectLater(
      Ciach(
        .new(rootPath: packagePath, dartExecutable: proxyDart(die: true)),
      ).run(),
      throwsA(
        isA<AnalysisServerExitedException>()
            .having((e) => e.exitCode, 'exitCode', 3)
            .having((e) => e.stderr, 'stderr', contains('Injected crash')),
      ),
    );
  });

  group('the CLI', () {
    Future<ProcessResult> runCli(String dart, [List<String> args = const []]) =>
        Process.run(Platform.resolvedExecutable, [
          'run',
          p.join('bin', 'ciach.dart'),
          packagePath,
          '--no-progress',
          '--dart',
          dart,
          ...args,
        ]);

    test(
      'reports the declaration as not analyzed and exits as usual',
      () async {
        final result = await runCli(proxyDart(), ['--set-exit-if-changed']);
        expect(
          result.exitCode,
          1,
          reason: '${result.stdout}\n${result.stderr}',
        );
        final stdout = result.stdout as String;
        final notAnalyzed = stdout.indexOf('Not analyzed (1)');
        expect(notAnalyzed, isNonNegative, reason: stdout);
        final findings = stdout.substring(0, notAnalyzed);
        expect(findings, contains('reallyUnused'));
        expect(findings, isNot(contains('brokenLookup')));
        expect(
          stdout.substring(notAnalyzed),
          allOf(
            contains(
              '  Could not find references; kept.\n'
              '    Injected failure\n'
              '    lib/a.dart\n'
              '      1:6  brokenLookup\n',
            ),
            contains('-v shows the stack traces'),
            contains('· 1 not analyzed'),
            isNot(contains('#0')),
          ),
        );
        // Problems are results, so stderr stays clean.
        expect(result.stderr, isNot(contains('brokenLookup')));
      },
    );

    test('with -v, narrates the problem once as it happens', () async {
      final result = await runCli(proxyDart(), ['-v']);
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      final stderr = result.stderr as String;
      expect(
        '[finder]  lib/a.dart:1:6 (brokenLookup): '.allMatches(stderr),
        hasLength(1),
        reason: stderr,
      );
      expect(result.stdout, contains('      #0      injected'));
    });

    test('says the server died, without a stack trace', () async {
      final result = await runCli(proxyDart(die: true));
      expect(result.exitCode, 2, reason: '${result.stdout}\n${result.stderr}');
      expect(
        result.stderr,
        allOf(
          contains('error: The Dart analysis server'),
          contains('exited unexpectedly with code 3'),
          contains('Injected crash'),
          isNot(contains('#0')),
        ),
      );
    });
  });
}

String _quoted(String path) => "'${path.replaceAll("'", r"'\''")}'";
