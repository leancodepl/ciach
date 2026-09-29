import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/cli/errors.dart';
import 'package:test/test.dart';

void main() {
  final stack = StackTrace.fromString('#0      main (file:///x.dart:1:1)');

  test('a server that died says so, without a stack trace', () {
    final text = describeFatalError(
      const AnalysisServerExitedException(
        executable: 'dart',
        exitCode: 255,
        stderr: 'Out of memory',
      ),
      stack,
      verbose: false,
    );
    expect(
      text,
      'error: The Dart analysis server (`dart language-server`) exited '
      'unexpectedly with code 255.\nIts stderr:\nOut of memory\n',
    );
  });

  test('a failed request points at --verbose for the server stack', () {
    const error = LspRequestException(
      'initialize',
      'Bad state',
      detail: '#0      Server.init',
    );
    expect(
      describeFatalError(error, stack, verbose: false),
      'error: The Dart analysis server failed initialize: Bad state.\n'
      'The analysis server threw while answering, which is likely a Dart SDK '
      'bug; --verbose shows its stack trace.\n',
    );
    expect(
      describeFatalError(error, stack, verbose: true),
      allOf(
        contains('The analysis server logged:\n#0      Server.init'),
        endsWith('#0      main (file:///x.dart:1:1)\n'),
      ),
    );
  });

  test('a failed removal names the files it already rewrote', () {
    expect(
      describeFatalError(
        const RemovalException(
          filePath: 'lib/b.dart',
          cause: 'Permission denied',
          changedFiles: ['lib/a.dart'],
        ),
        stack,
        verbose: false,
      ),
      'error: Could not remove declarations from lib/b.dart: Permission '
      'denied. Already rewritten, so review them before running again: '
      'lib/a.dart.\n',
    );
  });

  test('a file system error reads as one line', () {
    expect(
      describeFatalError(
        const FileSystemException(
          'Cannot open file',
          'lib/a.dart',
          OSError('No such file or directory', 2),
        ),
        stack,
        verbose: false,
      ),
      'error: Cannot open file: lib/a.dart: No such file or directory\n',
    );
  });

  test('anything else is a ciach bug: asks for a report', () {
    final text = describeFatalError(
      RangeError('Index out of range'),
      stack,
      verbose: false,
    );
    expect(text, startsWith('error: Internal error: RangeError'));
    expect(text, contains('This is a bug in ciach'));
    expect(text, contains('https://github.com/leancodepl/ciach/issues'));
    expect(text, endsWith('Run with --verbose to see the stack trace.\n'));
    expect(text, isNot(contains('#0')));

    expect(
      describeFatalError(RangeError('x'), stack, verbose: true),
      allOf(contains('#0      main'), isNot(contains('Run with --verbose'))),
    );
  });
}
