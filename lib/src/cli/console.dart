import 'dart:async';
import 'dart:io' as io;

import 'package:ciach/src/cli/log_format.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';

/// The CLI's terminal; the only code that touches stdio. Results go to stdout
/// via [output], log records to stderr via [attach].
final class Console {
  Console({
    required StringSink out,
    required StringSink err,
    bool outSupportsAnsi = false,
    bool errSupportsAnsi = false,
    Map<String, String> environment = const {},
    String? Function()? readLine,
    this.interactive = false,
    this.errIsTerminal = false,
    this.width,
  }) : _out = out,
       _err = err,
       _outSupportsAnsi = outSupportsAnsi,
       _errSupportsAnsi = errSupportsAnsi,
       _environment = environment,
       _readLine = readLine ?? (() => null) {
    configure();
  }

  /// The process's stdio.
  factory Console.standard() => Console(
    out: io.stdout,
    err: io.stderr,
    outSupportsAnsi: io.stdout.supportsAnsiEscapes,
    errSupportsAnsi: io.stderr.supportsAnsiEscapes,
    environment: io.Platform.environment,
    readLine: io.stdin.readLineSync,
    interactive: io.stdin.hasTerminal,
    errIsTerminal: io.stderr.hasTerminal,
    width: io.stderr.hasTerminal ? io.stderr.terminalColumns : null,
  );

  final StringSink _out;
  final StringSink _err;
  final bool _outSupportsAnsi;
  final bool _errSupportsAnsi;
  final Map<String, String> _environment;
  final String? Function() _readLine;

  /// Whether someone is there to answer [confirm].
  final bool interactive;

  /// Whether stderr is a terminal.
  final bool errIsTerminal;

  /// Terminal width; the progress line is cut to it.
  final int? width;

  final _clock = Stopwatch()..start();

  var _outStyle = Style.plain;
  var _formatter = const LogFormatter();
  var _progress = false;

  /// Length of the progress line on screen; 0 when none.
  var _progressLength = 0;

  /// Style for stdout.
  Style get outStyle => _outStyle;

  /// Style for stderr.
  Style get errStyle => _formatter.style;

  /// The lowest level shown.
  Level get level => _formatter.verbose
      ? .ALL
      : _progress
      ? .INFO
      : .WARNING;

  /// Applies the CLI options. [verbose] overrides [progress].
  void configure({bool? color, bool progress = false, bool verbose = false}) {
    Style styleFor(bool supportsAnsi) => .new(
      enabled: Style.shouldStyle(
        color: color,
        supportsAnsiEscapes: supportsAnsi,
        environment: _environment,
      ),
    );
    _outStyle = styleFor(_outSupportsAnsi);
    _formatter = .new(style: styleFor(_errSupportsAnsi), verbose: verbose);
    _progress = progress && !verbose;
    Logger.root.level = level;
  }

  /// Shows every log record from now on.
  StreamSubscription<LogRecord> attach() {
    Logger.root.level = level;
    return Logger.root.onRecord.listen(log);
  }

  /// Writes the result to stdout.
  void output(String text) {
    clearProgress();
    _out.write(text.endsWith('\n') ? text : '$text\n');
  }

  /// Asks [question] on stderr; `true` for yes.
  bool confirm(String question, {String? preamble}) {
    clearProgress();
    if (preamble != null) {
      _err.write(preamble.endsWith('\n') ? preamble : '$preamble\n');
    }
    _err.write('${errStyle.heading(question)} [y/N] ');
    return switch (_readLine()?.trim().toLowerCase()) {
      'y' || 'yes' => true,
      _ => false,
    };
  }

  /// Shows [record] as a line, or on the progress line.
  void log(LogRecord record) {
    if (record.level >= .WARNING || _formatter.verbose) {
      clearProgress();
      _err.write(_formatter.line(record, _clock.elapsed));
    } else if (_progress && record.level == Level.INFO) {
      _showProgress(record.message);
    }
  }

  /// Clears the progress line.
  void clearProgress() {
    if (_progressLength == 0) {
      return;
    }
    _err.write(errStyle.enabled ? '\r\x1b[2K' : '\r${' ' * _progressLength}\r');
    _progressLength = 0;
  }

  void _showProgress(String message) {
    final max = width;
    // A line filling the whole width wraps on some terminals.
    final text = max != null && message.length >= max
        ? '${message.substring(0, max - 2)}…'
        : message;
    final padding = ' ' * (_progressLength - text.length).clamp(0, 1 << 16);
    _err.write('\r${_formatter.progress(text)}$padding');
    _progressLength = text.length;
  }
}
