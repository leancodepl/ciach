import 'dart:async';
import 'dart:io' as io;

import 'package:ciach/src/style.dart';
import 'package:logging/logging.dart';

/// Everything the CLI writes to the terminal.
///
/// stdout carries the report alone, so `-f json` stays machine-readable.
/// Everything else goes to stderr: the progress line, `--verbose` narration,
/// warnings and errors. Each stream has its own [Style], since one can be a
/// terminal while the other is piped.
final class Console {
  Console({
    required StringSink out,
    required StringSink err,
    this.outStyle = Style.plain,
    this.errStyle = Style.plain,
    this.progress = false,
    this.verbose = false,
    this.width,
  }) : _out = out,
       _err = err;

  /// The process's stdout and stderr. [color] forces styling on or off for
  /// both; unset, each stream decides for itself.
  factory Console.standard({
    bool? color,
    bool progress = false,
    bool verbose = false,
  }) => Console(
    out: io.stdout,
    err: io.stderr,
    outStyle: Style.of(io.stdout, color: color),
    errStyle: Style.of(io.stderr, color: color),
    progress: progress && !verbose,
    verbose: verbose,
    width: io.stderr.hasTerminal ? io.stderr.terminalColumns : null,
  );

  final StringSink _out;
  final StringSink _err;

  final Style outStyle;
  final Style errStyle;

  /// Whether log records show on one line of stderr, each overwriting the
  /// last. Off with [verbose], whose lines are meant to stay.
  final bool progress;

  /// Whether every log record is printed, stamped with the time since this
  /// console was made.
  final bool verbose;

  /// The terminal's width, to keep the progress line from wrapping (and so
  /// from being overwritten only in part).
  final int? width;

  final _clock = Stopwatch()..start();

  /// The length of the progress line on screen, or 0 when there is none.
  var _progressLength = 0;

  /// Writes [text] to stdout as is.
  void report(String text) {
    clearProgress();
    _out.write(text);
  }

  /// Writes [text] to stderr as is.
  void write(String text) {
    clearProgress();
    _err.write(text);
  }

  /// Writes a line to stderr.
  void line([String text = '']) => write('$text\n');

  /// An `error:` line on stderr.
  void error(String message) => line('${errStyle.error('error:')} $message');

  /// A `warning:` line on stderr.
  void warning(String message) =>
      line('${errStyle.warning('warning:')} $message');

  /// A `--verbose` line; nothing otherwise.
  void trace(String message) {
    if (verbose) {
      line('${_stamp()} $message');
    }
  }

  /// Shows [record] as the configuration asks: every record when [verbose],
  /// else [Level.INFO] records on the progress line. Finer records are
  /// `--verbose` detail; warnings are left to the report, which groups them.
  void log(LogRecord record) {
    if (verbose) {
      final message = switch (record.level) {
        >= Level.SEVERE => errStyle.error(record.message),
        >= Level.WARNING => errStyle.yellow(record.message),
        _ => record.message,
      };
      line('${_stamp()} $message');
    } else if (progress && record.level == Level.INFO) {
      _showProgress(record.message);
    }
  }

  /// Routes the records of [logger] and its children to [log], at the level
  /// this console shows. Cancel the subscription when the run is done.
  StreamSubscription<LogRecord> listen([Logger? logger]) {
    Logger.root.level = verbose
        ? Level.FINE
        : progress
        ? Level.INFO
        : Level.WARNING;
    final name = logger?.fullName;
    return Logger.root.onRecord
        .where(
          (r) =>
              name == null ||
              r.loggerName == name ||
              r.loggerName.startsWith('$name.'),
        )
        .listen(log);
  }

  /// Clears the progress line, if one is showing.
  void clearProgress() {
    if (_progressLength == 0) {
      return;
    }
    _err.write(errStyle.enabled ? '\r\x1b[2K' : '\r${' ' * _progressLength}\r');
    _progressLength = 0;
  }

  void _showProgress(String message) {
    final max = width;
    // One column spare: a line that fills the terminal wraps on some.
    final text = max != null && message.length >= max
        ? '${message.substring(0, max - 2)}…'
        : message;
    final padding = ' ' * (_progressLength - text.length).clamp(0, 1 << 16);
    _err.write('\r${errStyle.hint(text)}$padding');
    _progressLength = text.length;
  }

  String _stamp() {
    final seconds = (_clock.elapsedMilliseconds / 1000).toStringAsFixed(1);
    return errStyle.hint('[${seconds.padLeft(5)}s]');
  }
}
