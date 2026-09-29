import 'dart:io' as io;

import 'package:ciach/src/cli/errors.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/style.dart';
import 'package:logging/logging.dart';

/// Everything the CLI writes to the terminal.
///
/// stdout carries the command's output alone ([report]), so `-f json` stays
/// machine-readable. Everything else is a log record, shown on stderr by
/// [log]: errors, warnings, the progress line and `--verbose` narration. Each
/// stream has its own [Style], since one can be a terminal while the other
/// is piped.
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

  /// A `--verbose` line; nothing otherwise.
  void trace(String message) {
    if (verbose) {
      line('${_stamp()} $message');
    }
  }

  /// The least a record needs to be shown; set [Logger.root]'s level to it.
  Level get level => verbose
      ? Level.FINE
      : progress
      ? Level.INFO
      : Level.WARNING;

  /// Shows [record] on stderr:
  ///
  /// - [Level.SEVERE] as an `error:` line, or, when it carries an error, as
  ///   everything [describeFatalError] has to say about it;
  /// - [Level.WARNING] as a `warning:` line, except an [AnalysisProblem],
  ///   which the report groups with the rest (shown here only when
  ///   [verbose]);
  /// - [Level.INFO] on the progress line, or as a [verbose] line;
  /// - anything finer as a [verbose] line only.
  void log(LogRecord record) {
    final level = record.level;
    final stamp = verbose ? '${_stamp()} ' : '';
    if (level >= Level.SEVERE) {
      write(switch (record.error) {
        final error? => describeFatalError(
          error,
          record.stackTrace ?? StackTrace.empty,
          verbose: verbose,
          style: errStyle,
        ),
        null => '${errStyle.error('error:')} ${record.message}\n',
      });
    } else if (level >= Level.WARNING) {
      if (record.object is! AnalysisProblem || verbose) {
        line('$stamp${errStyle.warning('warning:')} ${record.message}');
      }
    } else if (verbose) {
      line('$stamp${record.message}');
    } else if (progress && level == Level.INFO) {
      _showProgress(record.message);
    }
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
