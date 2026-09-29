import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/remover.dart';
import 'package:ciach/src/style.dart';
import 'package:ciach/src/version.dart';

const _issueTracker = 'https://github.com/leancodepl/ciach/issues';

/// A fatal [error] for stderr. The stack trace is shown only when [verbose].
String describeFatalError(
  Object error,
  StackTrace stackTrace, {
  required bool verbose,
  Style style = .plain,
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
  final buffer = StringBuffer()
    ..writeln('${style.errorLabel('error:')} $message');
  if (detail != null) {
    buffer.writeln(
      verbose
          ? 'Server stack trace:\n${style.detail(detail)}'
          : style.detail('Likely a Dart SDK bug; -v shows the stack trace.'),
    );
  }
  if (isBug) {
    buffer.writeln(
      'This is a bug in ciach $ciachVersion; please report it at '
      '$_issueTracker with the -v output.',
    );
  }
  if (verbose) {
    buffer
      ..writeln()
      ..writeln(style.detail('$stackTrace'.trimRight()));
  } else if (isBug) {
    buffer.writeln(style.detail('Run with -v for the stack trace.'));
  }
  return buffer.toString();
}
