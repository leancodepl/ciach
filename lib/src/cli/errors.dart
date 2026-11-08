import 'dart:io';

import 'package:ciach/src/analysis/language_versions.dart';
import 'package:ciach/src/remove/remover.dart';
import 'package:ciach/src/report/style.dart';
import 'package:ciach/src/version.dart';
import 'package:ciach/src/workspace/dart_executable.dart';
import 'package:ciach/src/workspace/packages.dart';

const _issueTracker = 'https://github.com/leancodepl/ciach/issues';

/// A fatal [error] for stderr. The stack trace is shown only when [verbose],
/// and only for a bug in ciach: an error the user can fix, such as a package
/// without `pub get`, has no use for it.
String describeFatalError(
  Object error,
  StackTrace stackTrace, {
  required bool verbose,
  Style style = .plain,
}) {
  final (message, isBug) = switch (error) {
    DartSdkNotFoundException(:final message) ||
    RemovalException(:final message) ||
    UnresolvedPackagesException(:final message) ||
    UnsupportedLanguageVersionException(:final message) => (message, false),
    FileSystemException(:final message, :final path, :final osError) => (
      [message, ?path, ?osError?.message].join(': '),
      false,
    ),
    _ => ('Internal error: $error', true),
  };
  final buffer = StringBuffer()
    ..writeln('${style.errorLabel('error:')} $message');
  if (isBug) {
    buffer.writeln(
      'This is a bug in ciach $ciachVersion; please report it at $_issueTracker with the -v output.',
    );
    if (verbose) {
      buffer
        ..writeln()
        ..writeln(style.detail('$stackTrace'.trimRight()));
    } else {
      buffer.writeln(style.detail('Run with -v for the stack trace.'));
    }
  }
  return buffer.toString();
}
