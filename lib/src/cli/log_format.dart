import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';

/// How a log record reads on stderr: the one place its look is decided. See
/// `log.dart` for what each level means.
final class LogFormatter {
  const LogFormatter({this.style = Style.plain, this.verbose = false});

  final Style style;

  /// Whether lines are stamped with the time and the logger's area, and
  /// fatal errors come with their stack trace.
  final bool verbose;

  /// Wide enough for every area: `finder`, `lsp`, `remover`, `cli`.
  static const _areaWidth = 7;

  /// [record] as lines that stay, ending with a newline. [elapsed] is the
  /// time since the run started, for the `--verbose` stamp.
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

  /// A [Level.INFO] record's [message] as the progress line shows it.
  String progress(String message) => style.detail(message);

  String _prefix(LogRecord record, Duration elapsed) {
    final seconds = (elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final name = record.loggerName;
    final area = name.startsWith('ciach.') ? name.substring(6) : name;
    return '${style.detail('[${seconds.padLeft(5)}s]')} '
        '${style.detail(area.padRight(_areaWidth))} ';
  }
}
