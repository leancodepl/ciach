/// One request failed; the server is still running.
class LspRequestException implements Exception {
  const LspRequestException(this.method, this.message, {this.detail});

  /// Parses a logged exception: message line, then stack trace.
  factory LspRequestException.fromLog(String method, String logged) {
    final newline = logged.indexOf('\n');
    return newline < 0
        ? .new(method, logged)
        : .new(
            method,
            logged.substring(0, newline),
            detail: logged.substring(newline + 1).trimRight(),
          );
  }

  /// The LSP method, e.g. `textDocument/references`.
  final String method;

  /// Why it failed, on one line.
  final String message;

  /// The server's stack trace, if logged.
  final String? detail;

  @override
  String toString() => 'The Dart analysis server failed $method: $message';
}

/// The analysis server exited unexpectedly.
class AnalysisServerExitedException implements Exception {
  const AnalysisServerExitedException({
    required this.executable,
    required this.exitCode,
    required this.stderr,
  });

  /// The `dart` the server was launched with.
  final String executable;

  final int exitCode;

  /// The server's stderr, trimmed.
  final String stderr;

  String get message =>
      '''
The Dart analysis server (`$executable language-server`) exited unexpectedly with code $exitCode.
${stderr.isEmpty ? 'It wrote nothing to stderr.' : 'Its stderr:\n$stderr'}''';

  @override
  String toString() => message;
}
