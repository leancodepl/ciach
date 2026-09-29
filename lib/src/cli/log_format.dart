import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';

/// Formats log records for stderr.
final class LogFormatter {
  const LogFormatter({this.style = Style.plain, this.verbose = false});

  final Style style;

  /// Adds a timestamp and logger area, and stack traces to fatal errors.
  final bool verbose;

  static const _areaWidth = 7;

  /// [record] as a line, newline-terminated.
  String line(LogRecord record, Duration elapsed) {
    final message = record.message;
    final text = switch (record.level) {
      >= Level.SEVERE => switch (record.error) {
        final error? => describeFatalError(
          error,
          record.stackTrace ?? StackTrace.empty,
          verbose: verbose,
          style: style,
        ).trimRight(),
        null => '${style.errorLabel('error:')} $message',
      },
      >= Level.WARNING => '${style.warningLabel('warning:')} $message',
      >= Level.INFO => message,
      >= Level.CONFIG => style.configuration(message),
      _ => style.detail(message),
    };
    return '${verbose ? _prefix(record, elapsed) : ''}$text\n';
  }

  /// [message] styled for the progress line.
  String progress(String message) => style.detail(message);

  String _prefix(LogRecord record, Duration elapsed) {
    final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final name = record.loggerName;
    final area = name.startsWith('ciach.') ? name.substring(6) : name;
    return '${style.detail('[${seconds.padLeft(5)}s]')} '
        '${style.detail(area.padRight(_areaWidth))} ';
  }
}
