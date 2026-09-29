import 'dart:async';
import 'dart:io' as io;

import 'package:ciach/src/cli/log_format.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/style.dart';

/// The CLI's terminal, and the only code in ciach that touches stdio.
///
/// It has two jobs, one per channel (see `log.dart`):
///
/// - the command's result goes to stdout through [output], so `-f json`
///   stays machine-readable;
/// - the log goes to stderr: [attach] makes this the sink for every record,
///   shown as [configure]d — warnings and errors always, [Level.INFO] on the
///   progress line, everything with `--verbose`.
///
/// Each stream is styled on its own, since one can be a terminal while the
/// other is piped.
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

  /// The process's stdio, styled where the terminal takes it, until
  /// [configure]d otherwise.
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

  /// Whether stderr is a terminal: where a progress line is worth showing.
  final bool errIsTerminal;

  /// The terminal's width, to keep the progress line from wrapping (and so
  /// from being overwritten only in part).
  final int? width;

  final _clock = Stopwatch()..start();

  var _outStyle = Style.plain;
  var _formatter = const LogFormatter();
  var _progress = false;

  /// The length of the progress line on screen, or 0 when there is none.
  var _progressLength = 0;

  /// How the result on stdout is styled.
  Style get outStyle => _outStyle;

  /// How stderr is styled.
  Style get errStyle => _formatter.style;

  /// The least a record needs to be shown.
  Level get level => _formatter.verbose
      ? Level.ALL
      : _progress
      ? Level.INFO
      : Level.WARNING;

  /// Applies the options: [color] forces styling on or off for both streams
  /// (unset, each decides for itself); [progress] shows [Level.INFO] records
  /// on one overwriting line; [verbose] shows every record as a line of its
  /// own, and supersedes [progress].
  void configure({bool? color, bool progress = false, bool verbose = false}) {
    Style styleFor(bool supportsAnsi) => Style(
      enabled: Style.shouldStyle(
        color: color,
        supportsAnsiEscapes: supportsAnsi,
        environment: _environment,
      ),
    );
    _outStyle = styleFor(_outSupportsAnsi);
    _formatter = LogFormatter(
      style: styleFor(_errSupportsAnsi),
      verbose: verbose,
    );
    _progress = progress && !verbose;
    Logger.root.level = level;
  }

  /// Makes this the sink for every log record. Cancel the subscription when
  /// the command is done.
  StreamSubscription<LogRecord> attach() {
    Logger.root.level = level;
    return Logger.root.onRecord.listen(log);
  }

  /// Writes the command's result to stdout.
  void output(String text) {
    clearProgress();
    _out.write(text.endsWith('\n') ? text : '$text\n');
  }

  /// Asks [question] on stderr, after [preamble] if any; `true` for a yes.
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

  /// Shows [record] on stderr, as a line of its own or on the progress line.
  void log(LogRecord record) {
    if (record.level >= Level.WARNING || _formatter.verbose) {
      clearProgress();
      _err.write(_formatter.line(record, _clock.elapsed));
    } else if (_progress && record.level == Level.INFO) {
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
    _err.write('\r${_formatter.progress(text)}$padding');
    _progressLength = text.length;
  }
}
