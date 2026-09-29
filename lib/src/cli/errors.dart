import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/remover.dart';
import 'package:ciach/src/style.dart';
import 'package:ciach/src/version.dart';

const _issueTracker = 'https://github.com/leancodepl/ciach/issues';

/// What stops a run, for stderr: what happened and what to do about it. The
/// stack trace is only shown when [verbose]; an error ciach did not expect
/// asks to be reported instead.
String describeFatalError(
  Object error,
  StackTrace stackTrace, {
  required bool verbose,
  Style style = Style.plain,
}) {
  final (message, detail, isBug) = switch (error) {
    AnalysisServerExitedException(:final message) => (message, null, false),
    LspRequestException(:final detail) => ('$error.', detail, false),
    RemovalException(:final message) => (message, null, false),
    ProcessException(:final executable, :final message) => (
      'Could not start `$executable`: $message',
      null,
      false,
    ),
    FileSystemException(:final message, :final path, :final osError) => (
      [message, ?path, ?osError?.message].join(': '),
      null,
      false,
    ),
    _ => ('Internal error: $error', null, true),
  };
  final buffer = StringBuffer()..writeln('${style.error('error:')} $message');
  if (detail != null) {
    buffer.writeln(
      verbose
          ? 'The analysis server logged:\n${style.hint(detail)}'
          : style.hint(
              'The analysis server threw while answering, which is likely a '
              'Dart SDK bug; --verbose shows its stack trace.',
            ),
    );
  }
  if (isBug) {
    buffer.writeln(
      'This is a bug in ciach $ciachVersion. Please report it at '
      '$_issueTracker, with the output of the same command run with --verbose.',
    );
  }
  if (verbose) {
    buffer
      ..writeln()
      ..writeln(style.hint('$stackTrace'.trimRight()));
  } else if (isBug) {
    buffer.writeln(style.hint('Run with --verbose to see the stack trace.'));
  }
  return buffer.toString();
}
