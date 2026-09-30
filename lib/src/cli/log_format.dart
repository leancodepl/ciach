import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';

/// Formats log records for stderr.
final class LogFormatter {
  const LogFormatter({this.style = .plain, this.verbose = false});

  final Style style;

  /// Adds a timestamp and logger area, and stack traces to fatal errors.
  final bool verbose;

  /// Fits `[remover]`, the longest area.
  static const _areaWidth = 9;

  /// The visible width of [_prefix]: `[  1.2s] [finder]  `.
  static const _prefixWidth = 8 + 1 + _areaWidth + 1;

  /// [record] as a line, newline-terminated.
  String line(LogRecord record, Duration elapsed) {
    final message = record.message;
    final text = switch (record.level) {
      >= .SEVERE => switch (record.error) {
        final error? => describeFatalError(
          error,
          record.stackTrace ?? .empty,
          verbose: verbose,
          style: style,
        ).trimRight(),
        null => '${style.errorLabel('error:')} $message',
      },
      >= .WARNING => '${style.warningLabel('warning:')} $message',
      >= .INFO => message,
      >= .CONFIG => style.configuration(message),
      _ => style.detail(message),
    };
    if (!verbose) {
      return '$text\n';
    }
    // Continuation lines start under the message, not the timestamp.
    final [first, ...rest] = text.split('\n');
    final indent = ' ' * _prefixWidth;
    return [
      '${_prefix(record, elapsed)}$first',
      for (final line in rest)
        if (line.isEmpty) line else '$indent$line',
    ].map((line) => '$line\n').join();
  }

  /// [message] styled for the progress line.
  String progress(String message) => style.detail(message);

  String _prefix(LogRecord record, Duration elapsed) {
    final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final name = record.loggerName;
    final area = name.startsWith('ciach.') ? name.substring(6) : name;
    return '${style.detail('[${seconds.padLeft(5)}s]')} '
        '${style.detail('[$area]'.padRight(_areaWidth))} ';
  }
}
